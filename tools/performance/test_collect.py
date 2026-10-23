import unittest
from collect import SegmentTracker, normalize_frame, build_command, source_timing, SampleCadence
class SampleTests(unittest.TestCase):
 def test_metrics_keep_bytes_and_units(self):
  t=SegmentTracker();r=normalize_frame({'pid':2,'physFootprint':1048576,'memResidentSize':2097152},3,t)
  self.assertEqual(r['metrics'],{'physicalFootprintBytes':1048576,'residentBytes':2097152});self.assertEqual(r['status'],'ok');self.assertEqual(r['segmentId'],1)
 def test_resident_does_not_replace_footprint(self):
  r=normalize_frame({'pid':2,'memResidentSize':99},0,SegmentTracker())
  self.assertEqual(r['status'],'unavailable');self.assertNotIn('physicalFootprintBytes',r['metrics'])
 def test_restart_and_pid_reuse_split(self):
  t=SegmentTracker()
  rows=[normalize_frame({'pid':pid,'startAbsTime':start,'physFootprint':1},i,t) for i,(pid,start) in enumerate([(2,5),(2,5),(3,6),(2,8)])]
  self.assertEqual([r['segmentId'] for r in rows],[1,1,2,3])
 def test_invalid_values_not_zero(self):
  for value in [-1,True,'12',float('nan')]:
   r=normalize_frame({'pid':2,'physFootprint':value},0,SegmentTracker());self.assertEqual(r['status'],'unavailable')
 def test_invalid_pid_rejected(self):
  self.assertEqual(normalize_frame({'pid':None,'physFootprint':1},0,SegmentTracker())['status'],'error')
 def test_command_follows_restarts(self):
  cmd=build_command('/pmd','udid','app',5,'/out/raw.jsonl')
  self.assertIn('--userspace',cmd);self.assertIn('--keep-monitoring',cmd);self.assertIn('name=app',cmd)
  self.assertNotIn('--native',cmd);self.assertIn('1000',cmd)
class SourceClockTests(unittest.TestCase):
 def test_buffered_samples_use_source_time(self):
  import datetime as dt
  start=dt.datetime.fromisoformat('2026-10-22T00:00:00+00:00')
  elapsed,age,error=source_timing({'timestamp':'2026-10-22T00:00:05+00:00'},start,10,5)
  self.assertEqual(elapsed,5);self.assertEqual(age,5);self.assertIsNone(error)
 def test_old_or_missing_timestamps_are_not_fresh(self):
  import datetime as dt
  start=dt.datetime.fromisoformat('2026-10-22T00:00:00+00:00')
  self.assertEqual(source_timing({'timestamp':'2026-10-22T00:00:01+00:00'},start,30,5)[2],'stale_source_sample')
  self.assertEqual(source_timing({},start,30,5)[2],'invalid_source_timestamp')
 def test_small_clock_lead_cannot_extend_capture(self):
  import datetime as dt
  start=dt.datetime.fromisoformat('2026-10-22T00:00:00+00:00')
  elapsed,age,error=source_timing({'timestamp':'2026-10-22T00:00:10.500000+00:00'},start,10,5)
  self.assertEqual(error,'future_source_sample');self.assertLessEqual(elapsed,10)
 def test_future_sample_is_invalid(self):
  import datetime as dt
  start=dt.datetime.fromisoformat('2026-10-22T00:00:00+00:00')
  self.assertEqual(source_timing({'timestamp':'2026-10-22T00:01:00+00:00'},start,10,5)[2],'future_source_sample')

class CollectorProcessTests(unittest.TestCase):
 def run_collector(self, body, seconds=1.8):
  import pathlib,tempfile,subprocess,sys,json
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp);fake=root/'pmd';out=root/'out'
   fake.write_text('#!'+sys.executable+'\nimport sys,json,time\nfrom pathlib import Path\np=Path(sys.argv[sys.argv.index("--output")+1])\n'+body);fake.chmod(0o755)
   r=subprocess.run([sys.executable,str(pathlib.Path(__file__).with_name('collect.py')),'--pmd',str(fake),'--udid','fake','--process','app','--interval','0.5','--seconds',str(seconds),'--out',str(out),'--ready-file',str(root/'ready.json')],capture_output=True,text=True,timeout=15)
   rows=[json.loads(l) for l in (out/'samples.jsonl').read_text().splitlines()]
   meta=json.loads((out/'collector-summary.json').read_text())
   meta['readyAcknowledgement']=json.loads((root/'ready.json').read_text()) if (root/'ready.json').exists() else None
   return r.returncode,rows,meta
 def test_no_stale_repetition_and_gaps_recorded(self):
  code,rows,meta=self.run_collector("p.write_text(json.dumps({'name':'app','pid':2,'timestamp':__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(),'physFootprint':123})+'\\n')\ntime.sleep(10)\n".replace("+'\\n'", "+'\\n'"))
  self.assertEqual(sum(r['status']=='ok' for r in rows),1)
  self.assertTrue(any(r['status']=='missing' for r in rows))
 def test_empty_stream_never_reports_valid_memory(self):
  code,rows,meta=self.run_collector('time.sleep(10)\n')
  self.assertEqual(code,1);self.assertEqual(meta['validSamples'],0)
  self.assertTrue(all(r['status']=='missing' for r in rows))

if __name__=='__main__':unittest.main()

class CadenceTests(unittest.TestCase):
 def test_fast_stream_retains_requested_period_and_pid_boundaries(self):
  c=SampleCadence(5)
  rows=[{'elapsedSeconds':t,'segmentId':seg} for t,seg in [(0,1),(1,1),(4,1),(5.1,1),(7,2),(8,2),(10.1,2)]]
  self.assertEqual([r['elapsedSeconds'] for r in rows if c.select(r)],[0,5.1,7,10.1])
 def test_missing_deadline_is_not_filled_with_previous_value(self):
  c=SampleCadence(5);c.select({'elapsedSeconds':0,'segmentId':1})
  self.assertEqual(c.missing(7.4),[])
  self.assertEqual(c.missing(7.6),[5])
  self.assertEqual(c.missing(8),[])
  self.assertTrue(c.select({'elapsedSeconds':10,'segmentId':2}))

class WarmupAndTailTests(CollectorProcessTests):
 def test_warmup_precedes_measurement_and_ready_requires_valid_frame(self):
  body="import datetime as dt\ntime.sleep(.9)\nfor i in range(7):\n with p.open('a') as f: f.write(json.dumps({'name':'app','pid':2,'timestamp':dt.datetime.now(dt.timezone.utc).isoformat(),'physFootprint':100+i})+'\\n')\n time.sleep(.2)\ntime.sleep(10)\n"
  code,rows,meta=self.run_collector(body,seconds=2.3)
  self.assertEqual(code,0);self.assertGreaterEqual(meta['warmupSeconds'],.8)
  self.assertEqual(rows[0]['elapsedSeconds'],0)
  self.assertTrue(all(r['status']=='ok' for r in rows))
  self.assertEqual(meta['readyAcknowledgement']['pid'],2)
 def test_shutdown_drains_final_real_frame(self):
  body="import datetime as dt,signal\ndef frame(value):\n with p.open('a') as f: f.write(json.dumps({'name':'app','pid':2,'timestamp':dt.datetime.now(dt.timezone.utc).isoformat(),'physFootprint':value})+'\\n')\ndef finish(*args):\n frame(999)\n raise SystemExit(0)\nsignal.signal(signal.SIGINT,finish)\nframe(123)\ntime.sleep(10)\n"
  code,rows,meta=self.run_collector(body,seconds=1.2)
  self.assertEqual(code,0)
  self.assertEqual([r for r in rows if r['status']=='ok'][-1]['metrics']['physicalFootprintBytes'],999)

class ShutdownWindowTests(CollectorProcessTests):
 def test_transport_cleanup_time_is_not_an_unsampled_test_window(self):
  body="import datetime as dt,signal\ndef finish(*args):\n time.sleep(1.2)\n raise SystemExit(0)\nsignal.signal(signal.SIGINT,finish)\np.write_text(json.dumps({'name':'app','pid':2,'timestamp':dt.datetime.now(dt.timezone.utc).isoformat(),'physFootprint':123})+'\\n')\ntime.sleep(10)\n"
  code,rows,meta=self.run_collector(body,seconds=.6)
  self.assertEqual(code,0)
  self.assertLess(meta['durationSeconds'],1)
  self.assertFalse(any(r['status']=='missing' for r in rows))
