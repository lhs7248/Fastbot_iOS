#!/usr/bin/env python3
"""Offline Fastbot report. Memory bytes are physical footprint, never RSS fallback."""
import argparse
import csv
from datetime import datetime, timedelta, timezone
import html
import json
import math
from pathlib import Path
import re

MIB = 1048576


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def valid(row):
    value = row.get('metrics', {}).get('physicalFootprintBytes')
    return (row.get('status') == 'ok' and isinstance(value, int) and
            not isinstance(value, bool) and value >= 0 and
            number(row.get('elapsedSeconds')) and row['elapsedSeconds'] >= 0 and
            type(row.get('pid')) is int and row['pid'] > 0 and
            type(row.get('segmentId')) is int and row['segmentId'] >= 0)


def summarize_samples(samples, interval_seconds=5, duration_seconds=None, growth_thresholds=None):
    if growth_thresholds is not None:
        if (not isinstance(growth_thresholds,dict) or
                not number(growth_thresholds.get('slopeMiBPerMin')) or growth_thresholds['slopeMiBPerMin']<0 or
                not number(growth_thresholds.get('peakOverBaselineRatio')) or growth_thresholds['peakOverBaselineRatio']<=1):
            raise ValueError('growth thresholds require finite slopeMiBPerMin >= 0 and peakOverBaselineRatio > 1')
    if not number(interval_seconds) or interval_seconds <= 0:
        raise ValueError('interval_seconds must be positive')
    rows = list(samples)
    if any(not isinstance(r, dict) or not isinstance(r.get('metrics', {}), dict) for r in rows):
        raise ValueError('sample rows and metrics must be objects')
    good = sorted((r for r in rows if valid(r)), key=lambda r: r['elapsedSeconds'])
    observed = max([r['elapsedSeconds'] for r in rows if number(r.get('elapsedSeconds'))] or [0])
    duration = observed if duration_seconds is None else duration_seconds
    if not number(duration) or duration < observed or duration < 0:
        raise ValueError('duration_seconds must cover all samples')
    gaps = [b-a for a,b in zip([0]+[r['elapsedSeconds'] for r in good], [r['elapsedSeconds'] for r in good]+[duration])]
    segments = []
    for row in good:
        identity = (row.get('segmentId'), row.get('pid'))
        if not segments or segments[-1]['identity'] != identity:
            segments.append({'identity': identity, 'rows': []})
        segments[-1]['rows'].append(row)
    out = []
    for segment in segments:
        points = segment['rows']; values = [r['metrics']['physicalFootprintBytes'] for r in points]
        baseline = sum(values[:5])/len(values[:5]); span = points[-1]['elapsedSeconds']-points[0]['elapsedSeconds']
        slope = None
        has_gap = any(b['elapsedSeconds']-a['elapsedSeconds']>interval_seconds*1.5 for a,b in zip(points,points[1:]))
        has_invalid = any(not valid(r) and (not number(r.get('elapsedSeconds')) or points[0]['elapsedSeconds'] <= r['elapsedSeconds'] <= points[-1]['elapsedSeconds']) for r in rows)
        if len(points) >= 3 and span >= max(10, interval_seconds*2) and not has_gap and not has_invalid:
            xs = [r['elapsedSeconds']/60 for r in points]; ys = [v/MIB for v in values]
            xm=sum(xs)/len(xs); ym=sum(ys)/len(ys)
            slope=sum((x-xm)*(y-ym) for x,y in zip(xs,ys))/sum((x-xm)**2 for x in xs)
        out.append(dict(segmentId=segment['identity'][0],pid=segment['identity'][1],sampleCount=len(points),
                        startedElapsedSeconds=points[0]['elapsedSeconds'],endedElapsedSeconds=points[-1]['elapsedSeconds'],
                        baselineBytes=baseline,peakBytes=max(values),endBytes=values[-1],deltaBytes=values[-1]-baseline,
                        slopeMiBPerMin=slope))
    # The initial t=0 attempt is optional; a partial final interval is not due.
    expected = max(1, math.floor(duration/interval_seconds))
    covered = len({int(r['elapsedSeconds'] // interval_seconds) for r in good
                   if int(r['elapsedSeconds'] // interval_seconds) < expected})
    max_gap=max(gaps or [duration]); failures=len(rows)-len(good)
    quality='failed' if not good else ('incomplete' if len(good)<3 or failures or max_gap>interval_seconds*1.5 or covered<expected else 'ok')
    sufficient=len(good)>=3 and any(s['slopeMiBPerMin'] is not None for s in out)
    growth=growth_thresholds is not None and any(s['slopeMiBPerMin'] is not None and s['slopeMiBPerMin']>growth_thresholds['slopeMiBPerMin'] and s['peakBytes']>s['baselineBytes']*growth_thresholds['peakOverBaselineRatio'] for s in out)
    risk='inconclusive' if not sufficient else ('not_configured' if growth_thresholds is None else ('suspicious_growth' if growth else 'no_growth_signal'))
    return dict(metric='physicalFootprintBytes',displayUnit='MiB',intervalSeconds=interval_seconds,durationSeconds=duration,
                expectedSampleConvention='Excludes optional t=0 sample and partial final interval; minimum one attempt.',
                expectedSampleCount=expected,sampledAttemptCount=len(rows),validSampleCount=len(good),failedSampleCount=failures,
                coverage=covered/expected,maxGapSeconds=max_gap,quality=quality,risk=risk,
                riskExplanation=('Growth thresholds are not configured; no memory health verdict is made.' if growth_thresholds is None else 'Configured growth thresholds are advisory, not proof of a leak; sparse data cannot establish healthy memory.'),
                growthThresholds=growth_thresholds,segments=out)


def read_json(path, default):
    if not path.exists(): return default
    try: return json.loads(path.read_text(encoding='utf-8'))
    except (ValueError, UnicodeError) as exc: raise ValueError('%s: %s' % (path,exc)) from exc


def curves(rows, interval):
    groups=[]; previous=None
    for row in sorted(rows,key=lambda r:r.get('elapsedSeconds') if number(r.get('elapsedSeconds')) else float('inf')):
        if not valid(row): previous=None; continue
        if previous is None or (row.get('pid'),row.get('segmentId')) != (previous.get('pid'),previous.get('segmentId')) or row['elapsedSeconds']-previous['elapsedSeconds']>interval*1.5:
            groups.append([])
        groups[-1].append(row); previous=row
    all_rows=[r for g in groups for r in g]
    xmax=max([r['elapsedSeconds'] for r in all_rows] or [1]) or 1
    ymax=max([r['metrics']['physicalFootprintBytes']/MIB for r in all_rows] or [1]) or 1
    lines=[]
    for group in groups:
        points=' '.join('%.2f,%.2f' % (40+r['elapsedSeconds']/xmax*900,220-r['metrics']['physicalFootprintBytes']/MIB/ymax*190) for r in group)
        lines.append('<polyline points="%s" fill="none" stroke="#167566" stroke-width="2" />' % points)
        for r in group:
            lines.append('<circle cx="%.2f" cy="%.2f" r="3" fill="#167566"><title>%.2f s: %.2f MiB</title></circle>' % (40+r['elapsedSeconds']/xmax*900,220-r['metrics']['physicalFootprintBytes']/MIB/ymax*190,r['elapsedSeconds'],r['metrics']['physicalFootprintBytes']/MIB))
    return '<svg viewBox="0 0 980 260" role="img" aria-label="Physical footprint in MiB over elapsed seconds; gaps are disconnected"><text x="5" y="15">MiB (max %.2f)</text><text x="800" y="250">Elapsed seconds (%.1f)</text>%s</svg>' % (ymax,xmax,''.join(lines))


def generate_report(results_dir):
    root=Path(results_dir); source=root/'performance/samples.jsonl'; rows=[]
    if source.exists():
        for i,line in enumerate(source.read_text(encoding='utf-8').splitlines(),1):
            if not line.strip(): continue
            try: row=json.loads(line)
            except ValueError as exc: raise ValueError('%s line %d: %s' % (source,i,exc)) from exc
            if not isinstance(row,dict): raise ValueError('%s line %d: expected object' % (source,i))
            rows.append(row)
    run=read_json(root/'run-summary.json',{}); monitor=read_json(root/'monitor/report.json',{})
    if not isinstance(run,dict) or not isinstance(monitor,dict): raise ValueError('run summary and monitor report must be objects')
    collector=read_json(root/'performance/collector-summary.json',{})
    if not isinstance(collector,dict): raise ValueError('collector summary must be an object')
    duration=collector.get('durationSeconds',run.get('durationSeconds'))
    capture=collector if collector.get('startedAt') and collector.get('endedAt') else run
    if duration is None and capture.get('startedAt') and capture.get('endedAt'):
        try: duration=(datetime.fromisoformat(capture['endedAt'].replace('Z','+00:00'))-datetime.fromisoformat(capture['startedAt'].replace('Z','+00:00'))).total_seconds()
        except (ValueError,TypeError) as exc: raise ValueError('Invalid run start/end timestamp') from exc
    summary=summarize_samples(rows,collector.get('intervalSeconds',run.get('sampleIntervalSeconds',run.get('memoryIntervalSeconds',5))),duration,run.get('memoryGrowthThresholds'))
    summary['collector']=collector
    if collector.get('failure') and summary['quality']=='ok': summary['quality']='incomplete'
    errors=monitor.get('errors',[])
    if not isinstance(errors,list) or any(not isinstance(e,dict) for e in errors): raise ValueError('monitor errors must be an array of objects')
    actions=[]; log=root/'monitor/fastbot.log'
    if log.exists():
        for line in log.read_text(encoding='utf-8').splitlines():
            match=re.search(r'^(\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d(?:\.\d+)?[+-]\d{4}).*?\bstate\s+(\S+)\s+action\s+(.*)',line)
            if match: actions.append(dict(timestamp=datetime.strptime(match[1].replace('T',' '), '%Y-%m-%d %H:%M:%S.%f%z' if '.' in match[1] else '%Y-%m-%d %H:%M:%S%z').isoformat(),state=match[2],action=match[3]))
    monitor_exit=monitor.get('exitCode',run.get('monitorExitCode',run.get('exitCode')))
    log_quality='unavailable' if not monitor or not number(monitor.get('targetLogLines')) or monitor.get('targetLogLines',0)<=0 else ('ok' if monitor.get('deviceStreamReady') is True and ((monitor.get('status') in ('passed','ok','completed','no_js_error_observed') and monitor_exit==0) or (monitor.get('status')=='js_error' and monitor_exit==2)) else 'incomplete')
    outcome='unknown' if monitor_exit is None else ('passed' if monitor_exit==0 else 'failed')
    issues={'testOutcome':outcome,'logQuality':log_quality,
            'memoryQuality':summary['quality'],'memoryRisk':summary['risk'],'nativeCrashStatus':'unverified',
            'errors':errors,'actions':actions,'pidRestarts':[s for i,s in enumerate(summary['segments']) if i and (s['pid'],s['segmentId'])!=(summary['segments'][i-1]['pid'],summary['segments'][i-1]['segmentId'])]}
    esc=lambda v:html.escape(str(v),quote=True)
    timeline=[]
    def add_event(stamp, kind, payload):
        instant=None
        if stamp:
            try:
                instant=datetime.fromisoformat(str(stamp).replace('Z','+00:00'))
                if instant.tzinfo is None: instant=None
            except (ValueError,TypeError): pass
        timeline.append({'timestamp':instant.astimezone(timezone.utc).isoformat().replace('+00:00','Z') if instant else None,
                         'sortTime':instant.timestamp() if instant else None,'kind':kind,'details':payload})
    for e in errors: add_event(e.get('observedAt'), 'JavaScript / monitor error',e)
    for a in actions: add_event(a['timestamp'],'Action',a)
    for segment in issues['pidRestarts']:
        stamp=None
        if collector.get('startedAt'):
            try:
                start=datetime.fromisoformat(collector['startedAt'].replace('Z','+00:00'))
                stamp=(start+timedelta(seconds=segment['startedElapsedSeconds'])).isoformat()
            except (ValueError,TypeError): pass
        add_event(stamp,'PID restart',segment)
    timeline.sort(key=lambda event:event['sortTime'] if event['sortTime'] is not None else float('inf'))
    issues['timeline']=timeline
    try:
        from .view import render_report
    except ImportError:
        from view import render_report
    (root/'performance').mkdir(parents=True,exist_ok=True)
    (root/'performance/summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    (root/'issues.json').write_text(json.dumps(issues,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    with (root/'performance/memory.csv').open('w',newline='',encoding='utf-8') as stream:
        fields=['timestamp','elapsedSeconds','pid','segmentId','status','physicalFootprintBytes','residentBytes','reason']; writer=csv.DictWriter(stream,fieldnames=fields); writer.writeheader()
        for r in rows: writer.writerow({k:(r.get('metrics',{}).get(k,'') if k in ('physicalFootprintBytes','residentBytes') else r.get(k,'')) for k in fields})
    page=render_report(run,monitor,collector,summary,issues,rows,root)
    (root/'report.html').write_text(page,encoding='utf-8')
    return {'summary':summary,'issues':issues,'reportPath':str(root/'report.html')}


def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('results',type=Path); args=parser.parse_args()
    try: result=generate_report(args.results)
    except (ValueError,OSError) as exc: parser.exit(1,'Report generation failed: %s\n'%exc)
    print(result['reportPath'])

if __name__=='__main__': main()
