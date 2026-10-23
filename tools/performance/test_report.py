import csv
import json
from pathlib import Path
import tempfile
import unittest
import report

MIB = 1048576

def sample(t, value=100, pid=12, segment=1, status='ok'):
    return dict(timestamp='2026-10-22T00:00:%02dZ' % t, elapsedSeconds=t,
                pid=pid, segmentId=segment, status=status,
                metrics={'physicalFootprintBytes': value * MIB})

class ReportTests(unittest.TestCase):
    def test_empty_and_insufficient_are_inconclusive(self):
        for rows in ([], [sample(0)], [sample(0), sample(5)]):
            s = report.summarize_samples(rows, duration_seconds=20)
            self.assertEqual(s['risk'], 'inconclusive')
            self.assertNotEqual(s['quality'], 'ok')

    def test_resident_is_never_main_metric(self):
        rows = [dict(sample(0), metrics={'residentBytes': 100*MIB}),
                dict(sample(5), metrics={'physicalFootprintBytes': True}),
                dict(sample(10), metrics={'physicalFootprintBytes': -1})]
        self.assertEqual(report.summarize_samples(rows)['validSampleCount'], 0)

    def test_segments_gaps_and_boundaries(self):
        rows = [sample(5), sample(10, 101), sample(15, 102), sample(30, 50, 13, 2)]
        s = report.summarize_samples(rows, duration_seconds=50)
        self.assertEqual(len(s['segments']), 2)
        self.assertEqual(s['maxGapSeconds'], 20)
        self.assertEqual(s['expectedSampleCount'], 10)
        self.assertEqual(s['sampledAttemptCount'], 4)
        self.assertEqual(s['segments'][0]['baselineBytes'], 101*MIB)
        self.assertEqual(s['quality'], 'incomplete')

    def test_growth_is_advisory_and_short_duration_has_no_slope(self):
        s = report.summarize_samples([sample(0, 100),sample(30,140),sample(60,200)], interval_seconds=30,growth_thresholds={'slopeMiBPerMin':1,'peakOverBaselineRatio':1.3})
        self.assertEqual(s['risk'], 'suspicious_growth')
        self.assertIn('advisory', s['riskExplanation'])
        self.assertIsNone(report.summarize_samples([sample(0),sample(1),sample(2)])['segments'][0]['slopeMiBPerMin'])

    def test_files_escape_html_preserve_bytes_and_render_gaps(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); (p/'performance').mkdir(); (p/'monitor').mkdir()
            rows=[sample(0),sample(5),sample(20),sample(25,110,13,2)]
            (p/'performance/samples.jsonl').write_text('\n'.join(json.dumps(r) for r in rows))
            (p/'monitor/report.json').write_text(json.dumps({'errors':[{'category':'JS','message':'<script>alert(1)</script>','observedAt':'2026-10-22T00:00:20Z','precedingLogContext':['<img>'],'followingLogContext':[]}]}))
            (p/'monitor/fastbot.log').write_text('2026-10-22 08:00:05.000+0800 state g0s1 action CLICK pos[1,2]\n')
            result=report.generate_report(p)
            h=(p/'report.html').read_text()
            self.assertNotIn('<script>alert',h); self.assertIn('&lt;script&gt;',h)
            self.assertGreaterEqual(h.count('<polyline '),3)
            self.assertIn('CLICK',h); self.assertIn('unverified',h)
            with (p/'performance/memory.csv').open() as f:
                self.assertEqual(int(next(csv.DictReader(f))['physicalFootprintBytes']),100*MIB)
            self.assertEqual(json.loads((p/'performance/summary.json').read_text())['validSampleCount'],4)
            self.assertTrue((p/'issues.json').is_file())

    def test_invalid_elapsed_does_not_crash_rendering(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); (p/'performance').mkdir()
            rows=[sample(0),dict(sample(5),elapsedSeconds=None)]
            (p/'performance/samples.jsonl').write_text('\n'.join(json.dumps(r) for r in rows))
            self.assertEqual(report.generate_report(p)['summary']['validSampleCount'],1)

    def test_collector_metadata_defines_capture_window_and_test_outcome(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); (p/'performance').mkdir()
            (p/'performance/collector-summary.json').write_text(json.dumps({'intervalSeconds':10,'durationSeconds':40,'collectorRetries':2,'failure':'late startup'}))
            (p/'run-summary.json').write_text(json.dumps({'exitCode':6,'monitorExitCode':0}))
            result=report.generate_report(p)
            self.assertEqual(result['summary']['durationSeconds'],40)
            self.assertEqual(result['summary']['expectedSampleCount'],4)
            self.assertEqual(result['summary']['collector']['collectorRetries'],2)
            self.assertEqual(result['issues']['testOutcome'],'passed')
            self.assertEqual(result['summary']['quality'],'failed')

    def test_collector_failure_prevents_ok_quality(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); (p/'performance').mkdir()
            (p/'performance/collector-summary.json').write_text(json.dumps({'intervalSeconds':5,'durationSeconds':10,'failure':'interrupted'}))
            (p/'performance/samples.jsonl').write_text('\n'.join(json.dumps(sample(t)) for t in (0,5,10)))
            self.assertEqual(report.generate_report(p)['summary']['quality'],'incomplete')
            self.assertIn('interrupted',(p/'report.html').read_text())

    def test_identity_and_gap_regression(self):
        for key,value in [('pid',None),('pid',0),('pid',True),('segmentId',None),('segmentId',-1)]:
            self.assertEqual(report.summarize_samples([dict(sample(0),**{key:value})])['validSampleCount'],0)
        for rows in ([sample(0),sample(5),sample(30)],
                     [sample(0),sample(5),sample(7,status='missing'),sample(10)]):
            self.assertIsNone(report.summarize_samples(rows)['segments'][0]['slopeMiBPerMin'])

    def test_monitor_quality_and_normalized_timeline(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); (p/'monitor').mkdir(); (p/'performance').mkdir()
            for monitor,quality in [({'status':'inconclusive','exitCode':0,'deviceStreamReady':True,'targetLogLines':2},'incomplete'),({'status':'passed','exitCode':0,'deviceStreamReady':True,'targetLogLines':0},'unavailable'),({'status':'no_js_error_observed','exitCode':0,'deviceStreamReady':True,'targetLogLines':2},'ok'),({'status':'js_error','exitCode':2,'deviceStreamReady':True,'targetLogLines':2},'ok')]:
                (p/'monitor/report.json').write_text(json.dumps(monitor))
                self.assertEqual(report.generate_report(p)['issues']['logQuality'],quality)
            (p/'performance/collector-summary.json').write_text(json.dumps({'startedAt':'2026-10-22T00:00:00Z','durationSeconds':20}))
            (p/'performance/samples.jsonl').write_text('\n'.join(json.dumps(r) for r in [sample(0),sample(10,pid=13,segment=2)]))
            (p/'monitor/report.json').write_text(json.dumps({'errors':[{'observedAt':'2026-10-22T08:00:15+08:00','message':'later-event'}]}))
            result=report.generate_report(p)
            timeline=result['issues']['timeline']
            self.assertEqual([e['kind'] for e in timeline],['PID restart','JavaScript / monitor error'])
            self.assertEqual(timeline[0]['timestamp'],'2026-10-22T00:00:10Z')

    def test_expected_count_excludes_optional_zero_and_partial_final_interval(self):
        rows=[dict(sample(0),elapsedSeconds=t) for t in (.2,5.2,10.2,15.2)]
        summary=report.summarize_samples(rows,duration_seconds=20.1)
        self.assertEqual(summary['expectedSampleCount'],4)
        self.assertEqual(summary['quality'],'ok')
        empty=report.summarize_samples([],duration_seconds=0)
        self.assertEqual(empty['expectedSampleCount'],1)
        self.assertEqual(empty['quality'],'failed')
        self.assertEqual(empty['risk'],'inconclusive')

    def test_growth_thresholds_optional_validated_and_same_pid_generation(self):
        rows=[sample(0),sample(5),sample(10)]
        self.assertEqual(report.summarize_samples(rows)['risk'],'not_configured')
        self.assertIsNone(report.summarize_samples(rows)['growthThresholds'])
        for thresholds in ({'slopeMiBPerMin':float('nan'),'peakOverBaselineRatio':1.3},{'slopeMiBPerMin':-1,'peakOverBaselineRatio':1.3},{'slopeMiBPerMin':1,'peakOverBaselineRatio':1}):
            with self.assertRaises(ValueError): report.summarize_samples(rows,growth_thresholds=thresholds)
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); (p/'performance').mkdir()
            (p/'run-summary.json').write_text(json.dumps({'memoryGrowthThresholds':{'slopeMiBPerMin':2,'peakOverBaselineRatio':1.5}}))
            (p/'performance/samples.jsonl').write_text('\n'.join(json.dumps(r) for r in rows+[sample(15,segment=2)]))
            result=report.generate_report(p)
            self.assertEqual(len(result['issues']['pidRestarts']),1)
            self.assertEqual(result['summary']['growthThresholds']['slopeMiBPerMin'],2)
            self.assertIn('1.5',(p/'report.html').read_text())

    def test_corrupt_input_is_not_silently_ignored(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d); (p/'performance').mkdir()
            (p/'performance/samples.jsonl').write_text('{broken')
            with self.assertRaises(ValueError): report.generate_report(p)

if __name__ == '__main__': unittest.main()

class CoverageTests(unittest.TestCase):
 def test_pid_boundary_extras_do_not_hide_an_empty_sampling_window(self):
  rows=[sample(0),sample(1,pid=13,segment=2),sample(2,pid=14,segment=3),sample(10,pid=14,segment=3),sample(15,pid=14,segment=3)]
  summary=report.summarize_samples(rows,duration_seconds=20)
  self.assertEqual(summary['coverage'],.75)
  self.assertEqual(summary['quality'],'incomplete')
