#!/usr/bin/env python3
"""Watch target-only iOS syslog; optionally fail/stop a Fastbot command on JS errors."""
import argparse, collections, datetime, json, math, os, queue, re, signal, subprocess, threading, time
from pathlib import Path

def detect_js_error(message):
    if 'FASTBOT_JS_ERROR' in message:
        return 'structured_js_exception'
    if re.search(r'Unhandled JS Exception|Unhandled JavaScript Exception', message, re.I):
        return 'unhandled_js_exception'
    if re.search(r'js engine:\s*hermes', message, re.I) and re.search(r'\b(?:Error|Exception)\b|\w+Error:', message):
        return 'js_engine_error'
    return None

def stop(process):
    if process and process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGINT)
        except ProcessLookupError:
            return
        try: process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()

def request_runner_stop(args, out, reason='js_error'):
    run_id = args.source_run_id
    if not run_id or not re.fullmatch(r'[A-Za-z0-9_-]{1,100}', run_id):
        return {'delivered':False, 'error':'Invalid source run identifier'}
    request = out/'stop-request.json'
    request.write_text(json.dumps({'runID':run_id, 'reason':reason,
        'requestedAt':datetime.datetime.now(datetime.timezone.utc).isoformat()}))
    command = ['xcrun','devicectl','device','copy','to','--device',args.udid,
        '--domain-type','appDataContainer','--domain-identifier',args.source_runner_bundle,
        '--source',str(request),'--destination','Documents/fastbot-evidence/'+run_id+'/stop.json',
        '--timeout','8']
    try:
        subprocess.run(command, check=True, timeout=10, capture_output=True)
        return {'delivered':True, 'method':'runner_control_file', 'graceSeconds':args.source_stop_grace}
    except (OSError, subprocess.SubprocessError) as exc:
        return {'delivered':False, 'error':str(exc)}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pmd', required=True, help='pymobiledevice3 executable')
    p.add_argument('--udid', required=True)
    p.add_argument('--process', default='hxl-host-app')
    p.add_argument('--seconds', type=float, default=90)
    p.add_argument('--out', required=True)
    p.add_argument('--source-run-id')
    p.add_argument('--source-runner-bundle', default='com.fastbot.local.runner.xctrunner')
    p.add_argument('--source-stop-grace', type=float, default=30)
    p.add_argument('--run', nargs=argparse.REMAINDER, help='Fastbot command; no shell evaluation')
    args = p.parse_args()
    if not math.isfinite(args.source_stop_grace) or args.source_stop_grace <= 0 or args.source_stop_grace > 60:
        p.error('--source-stop-grace must be > 0 and <= 60 seconds')
    if args.seconds <= 0:
        p.error('--seconds must be positive')
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=False)
    events = queue.Queue()
    context = collections.deque(maxlen=40)
    errors = []
    lines = 0
    collector = test = reader = None
    ready = False
    reason = None
    test_exit = None
    finish_deadline = error_deadline = None
    stop_request = None
    # The first device event confirms a live stream even when the target is idle.
    # Other-process events are discarded after this readiness check.
    log_cmd = [args.pmd, 'syslog', 'live', '--udid', args.udid, '--format', 'json']
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with (out/'device.log').open('w') as raw, (out/'collector.stderr.log').open('w') as err, (out/'fastbot.log').open('w') as test_log:
        try:
            collector = subprocess.Popen(log_cmd, stdout=subprocess.PIPE, stderr=err,
                                         text=True, bufsize=1, start_new_session=True)
            def read():
                try:
                    for line in collector.stdout:
                        events.put(line)
                finally:
                    events.put(None)
            reader = threading.Thread(target=read, daemon=True)
            reader.start()
            deadline = time.monotonic() + args.seconds
            ready_deadline = time.monotonic() + min(15, args.seconds)
            while True:
                now = time.monotonic()
                if test is not None and test.poll() is not None:
                    test_exit = test.returncode
                    if finish_deadline is None:
                        finish_deadline = now + 2
                if error_deadline is not None:
                    if finish_deadline is not None and now >= finish_deadline:
                        break
                    if now >= error_deadline:
                        if test is not None and test.poll() is None:
                            if stop_request is not None: stop_request['forcedTermination'] = True
                            stop(test)
                        break
                elif now >= deadline or (finish_deadline is not None and now >= finish_deadline):
                    reason = 'test_finished' if test_exit is not None else 'duration_elapsed'
                    break
                elif args.run and not ready and now >= ready_deadline:
                    reason = 'device_log_stream_not_ready'
                    break
                try:
                    line = events.get(timeout=0.2)
                except queue.Empty:
                    continue
                if line is None:
                    if not errors:
                        reason = 'collector_exited'
                    break
                try:
                    entry = json.loads(line)
                except (ValueError, TypeError):
                    continue
                if not isinstance(entry, dict) or not isinstance(entry.get('message'), str) or not isinstance(entry.get('filename'), str):
                    continue
                ready = True
                if Path(entry['filename']).name == args.process:
                    message = entry['message']
                    raw.write(line)
                    raw.flush()
                    lines += 1
                    for error in errors:
                        if len(error['followingLogContext']) < 40:
                            error['followingLogContext'].append(message)
                    category = detect_js_error(message)
                    if category:
                        errors.append({'observedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                       'category': category, 'message': message,
                                       'precedingLogContext': list(context), 'followingLogContext': []})
                        print('JS ERROR: ' + message, flush=True)
                        if error_deadline is None:
                            reason = 'js_error'
                            # Let the Runner stop actions and finalize XCTest attachments;
                            # force termination only if delivery or bounded cleanup fails.
                            if args.source_run_id and test is not None:
                                stop_request = request_runner_stop(args, out)
                            if stop_request and stop_request.get('delivered'):
                                error_deadline = time.monotonic() + args.source_stop_grace
                            else:
                                stop(test)
                                error_deadline = time.monotonic() + 2
                    context.append(message)
                if args.run and test is None and not errors:
                    test = subprocess.Popen(args.run, stdout=test_log, stderr=subprocess.STDOUT,
                                            start_new_session=True)
        except OSError as exc:
            reason = 'collection_or_test_launch_failed'
            print(str(exc), file=err, flush=True)
        except KeyboardInterrupt:
            reason = 'interrupted'
        finally:
            if test is not None and test.poll() is not None:
                test_exit = test.returncode
            stop(test)
            if test is not None: test_exit = test.returncode
            stop(collector)
            if reader is not None:
                reader.join(timeout=2)
            if collector is not None and collector.stdout is not None:
                collector.stdout.close()
    failed = reason in ('collector_exited', 'device_log_stream_not_ready',
                        'collection_or_test_launch_failed', 'interrupted')
    code = 2 if errors else 3 if failed else 4 if not lines else 5 if args.run and test_exit != 0 else 0
    report = {'startedAt': started, 'process': args.process, 'device': args.udid,
              'status': 'js_error' if errors else 'inconclusive' if code in (3,4,5) else 'no_js_error_observed',
              'reason': reason, 'deviceStreamReady': ready, 'targetLogLines': lines,
              'errors': errors, 'testExitCode': test_exit, 'exitCode': code, 'stopRequest':stop_request,
              'limitations': 'Only emitted device logs are observed; absence of a match does not prove JS health. No source maps or invisible/caught exceptions.'}
    (out/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps({k:v for k,v in report.items() if k != 'errors'}, ensure_ascii=False), flush=True)
    return code

if __name__ == '__main__':
    raise SystemExit(main())
