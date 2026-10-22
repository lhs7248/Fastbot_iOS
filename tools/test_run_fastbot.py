import unittest
from pathlib import Path
from run_fastbot import make_commands, load_settings
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
if __name__=='__main__':unittest.main()
