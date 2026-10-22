import unittest
from monitor import detect_js_error
class DetectionTests(unittest.TestCase):
 def test_js_engine_error(self):
  self.assertEqual(detect_js_error('ReferenceError: Property foo does not exist, js engine: hermes'), 'js_engine_error')
 def test_fatal_rn(self):
  self.assertEqual(detect_js_error('Unhandled JS Exception: TypeError: undefined is not a function'), 'unhandled_js_exception')
 def test_ordinary_native_error_is_not_js(self):
  self.assertIsNone(detect_js_error('Error Domain=NSURLErrorDomain Code=-1009'))
 def test_ordinary_hermes_info_is_not_error(self):
  self.assertIsNone(detect_js_error('Hermes runtime initialized successfully'))
 def test_structured_marker(self):
  self.assertEqual(detect_js_error('FASTBOT_JS_ERROR {"message":"boom"}'), 'structured_js_exception')

class MonitorProcessTests(unittest.TestCase):
 def run_monitor(self, body, extra=None):
  import pathlib,tempfile,subprocess,sys,json
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp);fake=root/'collector'
   fake.write_text('#!'+sys.executable+'\nimport builtins,json\n_rawprint=builtins.print\ndef print(*items, **kwargs):\n _rawprint(json.dumps({"filename":"/App/hxl-host-app","message":" ".join(str(x) for x in items)}),flush=True)\n'+body);fake.chmod(0o755)
   command=[sys.executable,str(pathlib.Path(__file__).with_name('monitor.py')),'--pmd',str(fake),'--udid','test-device','--seconds','0.8','--out',str(root/'out')]+(extra or [])
   r=subprocess.run(command,capture_output=True,text=True,timeout=15)
   return r.returncode,json.loads((root/'out/report.json').read_text())
 def test_error_fails_and_preserves_context(self):
  code,report=self.run_monitor("import time\nprint('screen opened',flush=True)\nprint('Unhandled JS Exception: TypeError: broken',flush=True)\ntime.sleep(5)\n")
  self.assertEqual(code,2);self.assertEqual(len(report['errors']),1)
  self.assertIn('screen opened',report['errors'][0]['precedingLogContext'])
 def test_silent_stream_is_inconclusive(self):
  code,report=self.run_monitor('import time\ntime.sleep(5)\n')
  self.assertEqual(code,4);self.assertEqual(report['status'],'inconclusive')
 def test_collector_failure_cannot_pass(self):
  code,report=self.run_monitor('raise SystemExit(1)\n')
  self.assertEqual(code,3);self.assertEqual(report['status'],'inconclusive')

 def test_js_error_stops_running_test(self):
  import sys, time
  start=time.monotonic()
  code,report=self.run_monitor("import time\nprint('target ready',flush=True)\ntime.sleep(0.2)\nprint('Unhandled JS Exception: Error: boom',flush=True)\ntime.sleep(10)\n", ['--run',sys.executable,'-c','import time;time.sleep(10)'])
  self.assertEqual(code,2)
  self.assertLess(time.monotonic()-start,5)

 def test_following_stack_saved(self):
  code,report=self.run_monitor("import time\nprint('Unhandled JS Exception: TypeError: boom')\ntime.sleep(0.1)\nprint('    at checkout (app.js:42)')\ntime.sleep(5)\n")
  self.assertEqual(code,2)
  self.assertIn('checkout',str(report['errors'][0].get('followingLogContext',[])))
 def test_other_process_error_is_not_target_error(self):
  code,report=self.run_monitor("import time\n_rawprint(json.dumps({'filename':'/App/other','message':'Unhandled JS Exception: Error: unrelated'}),flush=True)\nprint('target healthy')\ntime.sleep(5)\n")
  self.assertEqual(code,0)
  self.assertEqual(report['targetLogLines'],1)
 def test_device_stream_readiness_starts_test_without_target_logs(self):
  import sys
  code,report=self.run_monitor("import time\n_rawprint(json.dumps({'filename':'/System/SpringBoard','message':'ready'}),flush=True)\ntime.sleep(5)\n", ['--run',sys.executable,'-c','raise SystemExit(0)'])
  self.assertEqual(report['testExitCode'],0)
  self.assertEqual(code,4)

if __name__ == '__main__': unittest.main()
