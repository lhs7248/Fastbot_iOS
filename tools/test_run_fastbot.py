import unittest
from pathlib import Path
from run_fastbot import make_commands, load_settings, make_performance_command
class EntryTests(unittest.TestCase):
 def settings(self):return dict(device='device-1',bundle_id='test.app',process='test-process',team='TEAM',minutes=2,throttle=300,pmd='/tool/pmd')
 def test_monitor_wraps_test_and_carries_budget(self):
  build,run,env=make_commands(Path('/project'),Path('/state'),Path('/results'),self.settings())
  self.assertIn('build-for-testing',build)
  self.assertIn('monitor.py',str(run))
  self.assertEqual(run[run.index('--seconds')+1],'300')
  self.assertEqual(run[run.index('--process')+1],'test-process')
  self.assertIn('test-without-building',run[run.index('--run')+1:])
  self.assertEqual(env['BUNDLEID'],'test.app')
  self.assertEqual(env['duration'],'2')
 def test_does_not_disable_signing_or_monitoring(self):
  build,run,_=make_commands(Path('/project'),Path('/state'),Path('/results'),self.settings())
  self.assertIn('DEVELOPMENT_TEAM=TEAM',build)
  self.assertFalse(any('CODE_SIGNING_ALLOWED=NO' in s for s in build))
  self.assertIn('--run',run)
 def test_invalid_minutes_rejected(self):
  with self.assertRaises(ValueError):load_settings({'device':'a','bundle_id':'b','process':'c','team':'d','minutes':0})
 def test_missing_identity_rejected(self):
  with self.assertRaises(ValueError):load_settings({'minutes':1})
 def test_performance_enabled_and_configurable_by_default(self):
  settings=load_settings(self.settings())
  self.assertEqual(settings['sample_interval'],5)
  cmd=make_performance_command(Path('/project'),Path('/results'),settings)
  self.assertIn('collect.py',str(cmd));self.assertIn('--interval',cmd)
  self.assertEqual(cmd[cmd.index('--seconds')+1],'300')
 def test_invalid_sample_interval(self):
  for interval in [0,-1,float('nan'),float('inf'),True]:
   with self.assertRaises(ValueError):load_settings({**self.settings(),'sample_interval':interval})

if __name__=='__main__':unittest.main()

class GrowthSettingsTests(unittest.TestCase):
 def test_thresholds_are_opt_in_and_paired(self):
  base={'device':'d','bundle_id':'a','process':'app','team':'t'}
  self.assertIsNone(load_settings(base)['memory_growth_rate'])
  with self.assertRaises(ValueError):load_settings({**base,'memory_growth_rate':1})
  self.assertEqual(load_settings({**base,'memory_growth_rate':1,'memory_growth_ratio':1.3})['memory_growth_ratio'],1.3)

class MeasurementLifecycleTests(unittest.TestCase):
 def exercise(self, memory_ok=True, interrupted=False):
  import tempfile,json,contextlib,io
  from unittest.mock import patch
  from run_fastbot import run_measurement
  class Process:
   returncode=0
   def poll(self):return self.returncode
   def wait(self):
    if interrupted:raise KeyboardInterrupt()
    return self.returncode
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);(p/'monitor').mkdir();(p/'performance').mkdir()
   (p/'monitor/report.json').write_text(json.dumps({'status':'no_js_error_observed','exitCode':0,'targetLogLines':3,'deviceStreamReady':True,'errors':[]}))
   rows=[{'elapsedSeconds':t,'timestamp':'2026-10-22T00:00:00+00:00','pid':2,'segmentId':1,'status':'ok','metrics':{'physicalFootprintBytes':100}} for t in [0,5,10,15]] if memory_ok else []
   (p/'performance/samples.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in rows))
   (p/'performance/collector-summary.json').write_text(json.dumps({'intervalSeconds':5,'durationSeconds':15}))
   settings={'device':'d','bundle_id':'a','process':'app','sample_interval':5,'pmd':'/pmd','minutes':1}
   with patch('run_fastbot.prepare_memory_target',return_value='actual-app') as prepare, patch('run_fastbot.wait_for_performance_ready',return_value={'startedAt':'ready','pid':2}) as ready, patch('run_fastbot.subprocess.Popen',side_effect=[Process(),Process()]) as launch,patch('performance.collect.stop_child') as cleanup,contextlib.redirect_stdout(io.StringIO()):
    code=run_measurement(p,p,settings,['fake-test','--process','old-name'],{},p)
   prepare.assert_called_once(); ready.assert_called_once()
   self.assertEqual(cleanup.call_args_list[0].kwargs['timeout'],30)
   self.assertIn('collect.py',str(launch.call_args_list[0]))
   for call in launch.call_args_list:
    command=call.args[0]; self.assertEqual(command[command.index('--process')+1],'actual-app')
   self.assertTrue((p/'report.html').exists())
   if not memory_ok and not interrupted:self.assertIn('&quot;exitCode&quot;: 6',(p/'report.html').read_text())
   return code,json.loads((p/'run-summary.json').read_text())
 def test_completed_test_and_memory_keep_success(self):
  code,summary=self.exercise();self.assertEqual(code,0);self.assertEqual(summary['monitorExitCode'],0)
 def test_empty_memory_changes_overall_code_not_test_code(self):
  code,summary=self.exercise(memory_ok=False);self.assertEqual(code,6);self.assertEqual(summary['monitorExitCode'],0)
 def test_interrupt_still_generates_report(self):
  code,summary=self.exercise(interrupted=True);self.assertEqual(code,130);self.assertEqual(summary['reason'],'interrupted')

class SourceEngineEntryTests(unittest.TestCase):
 def test_source_is_default_and_invalid_engine_rejected(self):
  base=dict(device='d',bundle_id='b',process='p',team='t')
  self.assertEqual(load_settings(base)['engine'],'source')
  with self.assertRaises(ValueError):load_settings({**base,'engine':'unknown'})
 def test_podfile_selects_source_without_legacy_frameworks(self):
  from run_fastbot import workspace_podfile, engine_state
  source=workspace_podfile('source')
  self.assertIn("['source']",source)
  self.assertIn("['fastbot']",workspace_podfile('legacy'))
  self.assertNotEqual(engine_state(Path('/state'),'source'),engine_state(Path('/state'),'legacy'))

class MemoryReadyTests(unittest.TestCase):
 def test_readiness_requires_real_pid_and_first_sample(self):
  import tempfile,json
  from unittest.mock import Mock
  from run_fastbot import wait_for_performance_ready
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'ready.json';process=Mock();process.poll.return_value=None
   p.write_text(json.dumps({'startedAt':'now','pid':2}))
   self.assertEqual(wait_for_performance_ready(process,p)['pid'],2)
   p.write_text(json.dumps({'startedAt':'now','pid':None}))
   with self.assertRaises(OSError):wait_for_performance_ready(process,p)
 def test_failed_collector_does_not_start_test(self):
  import tempfile
  from unittest.mock import Mock
  from run_fastbot import wait_for_performance_ready
  with tempfile.TemporaryDirectory() as d:
   process=Mock();process.poll.return_value=1
   with self.assertRaises(OSError):wait_for_performance_ready(process,Path(d)/'missing.json')

class ProcessResolutionTests(unittest.TestCase):
 def test_process_name_comes_from_launch_result_not_bundle_or_config(self):
  import json,tempfile
  from unittest.mock import patch
  from run_fastbot import prepare_memory_target
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'performance-target.json').write_text(json.dumps({'result':{'process':{'processIdentifier':12,'executable':'file:///private/App/New.app/new-executable'}}}))
   with patch('run_fastbot.subprocess.run') as launch:
    self.assertEqual(prepare_memory_target({'device':'d','bundle_id':'bundle'},p),'new-executable')
   self.assertIn('--json-output',launch.call_args.args[0])

class EvidenceRunIdentityTests(unittest.TestCase):
 def test_scheme_forwards_per_run_identity_into_runner(self):
  import xml.etree.ElementTree as ET
  p=Path(__file__).resolve().parents[1]/'Fastbot-iOS/Fastbot-iOS.xcodeproj/xcshareddata/xcschemes/FastbotRunner.xcscheme'
  variables={e.get('key'):e.get('value') for e in ET.parse(p).iter('EnvironmentVariable')}
  self.assertEqual(variables.get('FASTBOT_RUN_ID'),'${FASTBOT_RUN_ID}')
