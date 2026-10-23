import tempfile
import unittest
from pathlib import Path
import report

class HumanReportTests(unittest.TestCase):
    def test_missing_data_is_not_presented_as_zero_or_healthy(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            report.generate_report(root)
            page=(root/'report.html').read_text()
            self.assertIn('lang="zh-CN"',page)
            self.assertIn('【数据不完整】',page)
            self.assertIn('无法判断是否发生 JS 异常',page)
            self.assertIn('<strong>未采集</strong><span>原生崩溃</span>',page)
            self.assertIn('尚未设置内存增长阈值',page)
            self.assertIn('<details><summary>技术详情与操作记录</summary>',page)
            self.assertIn('performance/memory.csv',page)
            self.assertNotIn('刷新',page)

    def test_exploration_effects_are_distinct_from_dispatch(self):
        import json
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            (root/'run-summary.json').write_text(json.dumps({'exploration':{'executed':8,'progressCount':3,'noEffectCount':4,'blockedActionCount':2,'recoveries':1,'completed':False,'stopReason':'no_progress_exhausted'}}))
            report.generate_report(root)
            page=(root/'report.html').read_text()
            self.assertIn('【探索受阻】',page)
            self.assertIn('探索效果',page)
            self.assertIn('已发出操作 8',page)
            self.assertIn('观测到界面变化 3',page)
            self.assertIn('未观测到变化 4',page)
            self.assertIn('候选动作耗尽',page)
            self.assertIn('界面变化不等于业务成功',page)

class FailureEvidenceReportTests(unittest.TestCase):
 def test_missing_evidence_is_shown_as_unknown_not_zero(self):
  import json
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);(root/'run-summary.json').write_text(json.dumps({'exploration':{'completed':False,'executed':None,'rejected':None,'evidenceStatus':'unavailable','stopReason':'evidence_unavailable','xcresultAvailable':False}}))
   report.generate_report(root);page=(root/'report.html').read_text()
   self.assertIn('【探索记录不完整】',page);self.assertIn('已发出操作 未采集',page)
   self.assertIn('导出诊断',page);self.assertNotIn('已发出操作 None',page)
