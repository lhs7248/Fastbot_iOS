#!/usr/bin/env python3
"""Collect iOS process footprint samples without modifying the tested app."""
import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import threading
import time


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


class SegmentTracker:
    def __init__(self):
        self.identity = None
        self.segment = 0

    def identify(self, frame):
        identity = (frame['pid'], frame.get('startAbsTime'))
        if identity != self.identity:
            self.identity = identity
            self.segment += 1
        return self.segment


def byte_value(value):
    # Instruments fields are byte counts. Missing/invalid values never become zero.
    return value if type(value) is int and value >= 0 else None


def normalize_frame(frame, elapsed, tracker):
    row = {'timestamp': frame.get('timestamp') or utc_now(), 'elapsedSeconds': elapsed,
           'pid': frame.get('pid'), 'segmentId': None, 'status': 'ok', 'metrics': {}}
    if type(row['pid']) is not int or row['pid'] <= 0:
        row.update(pid=None, status='error', reason='invalid_pid')
        return row
    row['segmentId'] = tracker.identify(frame)
    for source, target in [('physFootprint', 'physicalFootprintBytes'),
                           ('memResidentSize', 'residentBytes')]:
        value = byte_value(frame.get(source))
        if value is not None:
            row['metrics'][target] = value
    if 'physicalFootprintBytes' not in row['metrics']:
        row.update(status='unavailable', reason='physical_footprint_unavailable')
    return row


def source_timing(frame, start_wall, received_elapsed, interval):
    try:
        instant = dt.datetime.fromisoformat(frame['timestamp'].replace('Z', '+00:00'))
        if instant.tzinfo is None:
            raise ValueError('timezone missing')
        elapsed = (instant - start_wall).total_seconds()
    except (KeyError, ValueError, TypeError, AttributeError):
        return received_elapsed, 0, 'invalid_source_timestamp'
    age = received_elapsed - elapsed
    if elapsed < 0:
        return 0, age, 'source_sample_before_capture'
    if age < 0:
        return received_elapsed, age, 'future_source_sample'
    if age > max(10, interval * 3):
        return elapsed, age, 'stale_source_sample'
    return elapsed, max(0, age), None


class SampleCadence:
    """Select real frames at the requested cadence, retaining process boundaries."""
    def __init__(self, interval):
        self.interval = interval
        self.next_due = 0
        self.segment = None

    def select(self, row):
        elapsed = row['elapsedSeconds']
        due = elapsed >= self.next_due
        boundary = row['segmentId'] != self.segment
        if due:
            self.next_due = (math.floor(elapsed / self.interval) + 1) * self.interval
        if due or boundary:
            self.segment = row['segmentId']
            return True
        return False

    def missing(self, elapsed):
        missed = []
        while elapsed > self.next_due + self.interval * .5:
            missed.append(self.next_due)
            self.next_due += self.interval
        return missed


def build_command(pmd, udid, process, interval, raw_path):
    return [pmd, 'developer', 'dvt', 'sysmon', 'process', 'monitor', 'process',
            '--userspace', '--udid', udid, '--filter', 'name=' + process,
            '--choose', 'last', '--keep-monitoring', '--interval', str(round(min(1, interval / 3) * 1000)),
            '--output', str(raw_path)]


def stop_child(child, timeout=4):
    if child is None or child.poll() is not None:
        return
    try:
        os.killpg(child.pid, signal.SIGINT)
        child.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(child.pid, signal.SIGTERM)
            child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        except ProcessLookupError:
            pass
    except ProcessLookupError:
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pmd', required=True)
    parser.add_argument('--udid', required=True)
    parser.add_argument('--process', required=True)
    parser.add_argument('--interval', type=float, default=5)
    parser.add_argument('--seconds', type=float, default=900)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--ready-file', type=Path)
    args = parser.parse_args()
    if not math.isfinite(args.interval) or args.interval < .5:
        parser.error('--interval must be finite and >= 0.5 seconds')
    if not math.isfinite(args.seconds) or args.seconds <= 0:
        parser.error('--seconds must be finite and positive')
    args.out.mkdir(parents=True, exist_ok=True)
    raw_path = args.out/'raw-metrics.jsonl'
    raw_path.touch(exist_ok=False)
    stopped = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: stopped.set())
    tracker = SegmentTracker()
    cadence = SampleCadence(args.interval)
    warmup_started_at = utc_now()
    start_wall = dt.datetime.fromisoformat(warmup_started_at)
    start = time.monotonic()
    capture_offset = None
    started_at = None
    last_event_elapsed = -1
    last_source = None
    last_valid = None
    last_saved_elapsed = -1
    last_recorded_elapsed = 0
    child = None
    accepted = raw_valid = attempts = offset = 0
    terminal_failure = None
    with (args.out/'samples.jsonl').open('w') as sink, (args.out/'warmup.jsonl').open('w') as warmup, (args.out/'collector.log').open('w') as log:
        def elapsed_now():
            return max(0, time.monotonic() - start - (capture_offset or 0))

        def save(row):
            nonlocal accepted, last_saved_elapsed, last_recorded_elapsed
            sink.write(json.dumps(row, ensure_ascii=False, allow_nan=False) + '\n')
            sink.flush()
            last_recorded_elapsed = max(last_recorded_elapsed, row['elapsedSeconds'])
            accepted += row['status'] == 'ok'
            if row['status'] == 'ok':
                last_saved_elapsed = row['elapsedSeconds']

        def save_missing(elapsed):
            for due in cadence.missing(elapsed):
                stamp = (start_wall + dt.timedelta(seconds=capture_offset + due)).isoformat()
                save({'timestamp': stamp, 'elapsedSeconds': due, 'pid': None,
                      'segmentId': None, 'status': 'missing', 'metrics': {},
                      'reason': 'no_fresh_target_sample'})

        def consume():
            nonlocal offset, last_source, capture_offset, started_at, last_event_elapsed
            nonlocal last_valid, raw_valid
            with raw_path.open() as raw:
                raw.seek(offset)
                while True:
                    before = raw.tell()
                    line = raw.readline()
                    if not line or not line.endswith('\n'):
                        offset = before
                        break
                    offset = raw.tell()
                    received = time.monotonic() - start
                    try:
                        frame = json.loads(line)
                        if not isinstance(frame, dict):
                            raise ValueError('expected a JSON object')
                        if frame.get('name') != args.process:
                            continue
                        source = (frame.get('timestamp'), frame.get('pid'), frame.get('startAbsTime'))
                        if source == last_source and frame.get('timestamp'):
                            continue
                        last_source = source
                        source_elapsed, age, error = source_timing(frame, start_wall, received, args.interval)
                        if error is None and source_elapsed <= last_event_elapsed:
                            error = 'nonprogressing_source_sample'
                        if error is None:
                            last_event_elapsed = source_elapsed
                            row = normalize_frame(frame, source_elapsed, tracker)
                        else:
                            row = {'timestamp': frame.get('timestamp') or utc_now(),
                                   'elapsedSeconds': source_elapsed, 'pid': frame.get('pid'),
                                   'segmentId': None, 'status': 'error', 'metrics': {}, 'reason': error}
                    except (ValueError, TypeError) as exc:
                        row = {'timestamp': utc_now(), 'elapsedSeconds': received, 'pid': None,
                               'segmentId': None, 'status': 'error', 'metrics': {},
                               'reason': 'malformed_sample: ' + str(exc)}
                    if capture_offset is None:
                        if row['status'] != 'ok':
                            warmup.write(json.dumps(row, ensure_ascii=False) + '\n'); warmup.flush()
                            continue
                        capture_offset = row['elapsedSeconds']
                        started_at = row['timestamp']
                    row['elapsedSeconds'] = max(0, row['elapsedSeconds'] - capture_offset)
                    row['receivedElapsedSeconds'] = max(0, received - capture_offset)
                    if row['status'] == 'ok':
                        raw_valid += 1
                        save_missing(row['elapsedSeconds'])
                        last_valid = row
                        if cadence.select(row):
                            save(row)
                        if args.ready_file and not args.ready_file.exists():
                            temp = args.ready_file.with_suffix('.tmp')
                            temp.write_text(json.dumps({'startedAt': started_at,
                                'warmupSeconds': capture_offset, 'pid': row['pid']}))
                            temp.replace(args.ready_file)
                    else:
                        save(row)

        try:
            child = subprocess.Popen(build_command(args.pmd, args.udid, args.process,
                                                    args.interval, raw_path),
                                     stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            while not stopped.is_set() and time.monotonic() - start < args.seconds:
                consume()
                if capture_offset is not None:
                    save_missing(elapsed_now())
                if child.poll() is not None:
                    if capture_offset is not None:
                        save({'timestamp': utc_now(), 'elapsedSeconds': elapsed_now(),
                              'pid': None, 'segmentId': None, 'status': 'error', 'metrics': {},
                              'reason': 'collector_exited_' + str(child.returncode)})
                    attempts += 1
                    if attempts >= 3:
                        terminal_failure = 'collector_failed_after_retries'
                        break
                    if stopped.wait(min(2 * attempts, 6)):
                        break
                    raw_path = args.out / ('raw-metrics-retry-' + str(attempts) + '.jsonl')
                    raw_path.touch(exist_ok=False)
                    offset = 0
                    child = subprocess.Popen(build_command(args.pmd, args.udid, args.process,
                                                            args.interval, raw_path),
                                             stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                stopped.wait(min(.2, args.interval / 4))
        except (OSError, ValueError) as exc:
            terminal_failure = str(exc)
        finally:
            # Stop and drain the writer before closing the sampling window. Tail
            # points are actual source frames, never copies used to fill a gap.
            capture_stop_absolute = time.monotonic() - start
            shutdown_started = time.monotonic()
            stop_child(child)
            consume()
            capture_stop = max(0, capture_stop_absolute - (capture_offset or 0))
            if capture_offset is not None:
                save_missing(capture_stop)
                if last_valid and last_valid['elapsedSeconds'] > last_saved_elapsed:
                    save(last_valid)
            else:
                terminal_failure = terminal_failure or 'target_sample_not_ready'
                save({'timestamp': utc_now(), 'elapsedSeconds': 0, 'pid': None,
                      'segmentId': None, 'status': 'missing', 'metrics': {},
                      'reason': terminal_failure})
            capture_duration = max(capture_stop, last_recorded_elapsed) if capture_offset is not None else 0
            capture_end = (start_wall + dt.timedelta(seconds=(capture_offset or 0) + capture_duration)).isoformat()
            metadata = {'platform': 'ios', 'metric': 'physicalFootprintBytes', 'unit': 'bytes',
                        'process': args.process, 'device': args.udid,
                        'warmupStartedAt': warmup_started_at, 'warmupSeconds': capture_offset,
                        'startedAt': started_at, 'endedAt': capture_end if capture_offset is not None else utc_now(), 'durationSeconds': capture_duration,
                        'shutdownSeconds': time.monotonic() - shutdown_started,
                        'intervalSeconds': args.interval, 'sourceIntervalSeconds': min(1, args.interval / 3),
                        'validSamples': accepted, 'rawValidSamples': raw_valid,
                        'collectorRetries': attempts, 'failure': terminal_failure,
                        'stopReason': 'stopped' if stopped.is_set() else 'failed' if terminal_failure else 'budget_elapsed'}
            (args.out/'collector-summary.json').write_text(json.dumps(metadata, indent=2))
    return 0 if accepted and terminal_failure is None else 1


if __name__ == '__main__':
    raise SystemExit(main())
