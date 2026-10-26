import json,tempfile,unittest
from pathlib import Path
class SourceEvidenceTests(unittest.TestCase):
 def test_normalizes_actual_action_outcomes(self):
  from source_evidence import normalize_attachments
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder); raw=root/'raw';raw.mkdir()
   (raw/'events.json').write_text('\n'.join(json.dumps(r) for r in [dict(kind='action',act='CLICK',executed=True,state='a'),dict(kind='action',act='BACK',executed=False,reason='no_back_button'),dict(kind='summary',completed=True,executed=1,rejected=1,states=1)]))
   (raw/'manifest.json').write_text(json.dumps([{'attachments':[{'exportedFileName':'events.json','suggestedHumanReadableName':'source-exploration_0.jsonl'}]}]))
   summary=normalize_attachments(raw,root)
   self.assertEqual(summary['executed'],1);self.assertEqual(summary['rejected'],1)
   self.assertEqual(summary['rejectionReasons'],{'no_back_button':1})
   self.assertTrue((root/'exploration.jsonl').exists())
 def test_missing_or_traversal_attachment_rejected(self):
  from source_evidence import normalize_attachments
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);(root/'manifest.json').write_text(json.dumps([{'attachments':[{'exportedFileName':'../outside','suggestedHumanReadableName':'source-exploration.jsonl'}]}]))
   with self.assertRaises(ValueError):normalize_attachments(root,root)

 def test_effect_summary_must_match_observed_effects(self):
  from source_evidence import normalize_attachments
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder); raw=root/'raw';raw.mkdir()
   rows=[dict(kind='action',act='CLICK',executed=True),dict(kind='action_effect',effect='no_observable_change'),dict(kind='summary',completed=True,executed=1,rejected=0,noEffectCount=9,progressCount=0)]
   (raw/'events.json').write_text('\n'.join(json.dumps(r) for r in rows))
   (raw/'manifest.json').write_text(json.dumps([{'attachments':[{'exportedFileName':'events.json','suggestedHumanReadableName':'source-exploration_0.jsonl'}]}]))
   with self.assertRaises(ValueError):normalize_attachments(raw,root)
   rows[-1]['noEffectCount']=1
   (raw/'events.json').write_text('\n'.join(json.dumps(r) for r in rows))
   self.assertEqual(normalize_attachments(raw,root)['noEffectCount'],1)

class JournalRecoveryTests(unittest.TestCase):
 def test_final_device_journal_survives_invalid_xcresult(self):
  from source_evidence import recover_journal
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);j=p/'device';j.mkdir();out=p/'out';out.mkdir()
   rows=[{'kind':'action','act':'CLICK','executed':True},{'kind':'summary','completed':False,'stopReason':'external_js_error','executed':1,'rejected':0}]
   (j/'exploration.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in rows));(j/'last-tree.xml').write_text('<hierarchy/>')
   result=recover_journal(j,out,'js_error')
   self.assertEqual(result['evidenceStatus'],'complete');self.assertFalse(result['completed'])
   self.assertEqual(result['executed'],1);self.assertTrue((out/'last-tree.xml').exists())
 def test_truncated_tail_is_explicitly_partial_not_fabricated_success(self):
  from source_evidence import recover_journal
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);j=p/'device';j.mkdir();out=p/'out';out.mkdir()
   (j/'exploration.jsonl').write_text(json.dumps({'kind':'action','act':'CLICK','executed':True})+'\n'+ '{"kind":')
   result=recover_journal(j,out,'js_error')
   self.assertEqual(result['evidenceStatus'],'recovered_partial');self.assertEqual(result['executed'],1)
   self.assertFalse(result['completed']);self.assertIsNone(result['states'])
   self.assertTrue(result['tailMayBeMissing'])
 def test_corruption_in_middle_is_not_silently_accepted(self):
  from source_evidence import recover_journal
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);j=p/'device';j.mkdir();out=p/'out';out.mkdir()
   (j/'exploration.jsonl').write_text('{broken}\n'+json.dumps({'kind':'action','executed':True})+'\n')
   with self.assertRaises(ValueError):recover_journal(j,out,'js_error')

class ExportFallbackTests(unittest.TestCase):
 def test_journal_recovered_even_without_monitor_report_or_valid_xcresult(self):
  from unittest.mock import patch
  import subprocess
  from source_evidence import export_source_evidence
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'run-1';p.mkdir()
   def invoke(command, **kwargs):
    if 'devicectl' in command:
     j=p/'exploration/device';(j/'exploration.jsonl').write_text(json.dumps({'kind':'summary','completed':False,'executed':0,'rejected':0,'stopReason':'external_js_error'})+'\n')
     return subprocess.CompletedProcess(command,0)
    raise subprocess.CalledProcessError(64,command)
   with patch('source_evidence.subprocess.run',side_effect=invoke): result=export_source_evidence(p,'device')
   self.assertEqual(result['evidenceSource'],'device_journal')
   self.assertEqual(result['evidenceStatus'],'complete')
   self.assertFalse(result['xcresultAvailable'])

class SnapshotFailureTests(unittest.TestCase):
 def test_bad_snapshot_does_not_discard_valid_action_journal(self):
  from source_evidence import recover_journal
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);j=p/'device';j.mkdir();out=p/'out';out.mkdir()
   rows=[{'kind':'action','act':'CLICK','executed':True},{'kind':'summary','completed':False,'executed':1,'rejected':0}]
   (j/'exploration.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in rows))
   (j/'checkpoint.json').write_text('{"xml":')
   result=recover_journal(j,out,'js_error')
   self.assertEqual(result['executed'],1);self.assertEqual(result['evidenceStatus'],'recovered_partial')
   self.assertFalse(result['snapshotAvailable']);self.assertIn('snapshotError',result)

class ExplorationQualityTests(unittest.TestCase):
 def test_round_trips_are_not_reported_as_new_coverage(self):
  from source_evidence import summarize_events
  rows=[]
  for before,after in [('A','B'),('B','A'),('A','B'),('B','B'),('B','B')]:
   rows.append(dict(kind='action',act='CLICK',executed=True,beforeFingerprint=before))
   rows.append(dict(kind='action_effect',act='CLICK',beforeFingerprint=before,afterFingerprint=after,effect='changed' if before!=after else 'no_observable_change'))
  rows += [dict(kind='exploration_pass'),dict(kind='exploration_pass'),dict(kind='summary',executed=5,rejected=0,progressCount=3,noEffectCount=2)]
  result=summarize_events(rows)
  self.assertEqual(result['observedContextCount'],2)
  self.assertEqual(result['revisitedContextTransitions'],2)
  self.assertEqual(result['maxConsecutiveNoEffect'],2)
  self.assertEqual(result['explorationPassCount'],2)
 def test_legacy_missing_fingerprints_are_unknown_not_zero_coverage(self):
  from source_evidence import summarize_events
  result=summarize_events([dict(kind='action',executed=True),dict(kind='summary',executed=1,rejected=0)])
  self.assertIsNone(result['observedContextCount'])
  self.assertIsNone(result['revisitedContextTransitions'])

class TargetResolutionTests(unittest.TestCase):
 def test_lookup_details_count_only_failed_actions_and_remain_unknown_for_old_logs(self):
  from source_evidence import summarize_events
  rows=[dict(kind='action',executed=False,targetResolution={'reason':'no_hittable_target','lookups':[{'reason':'not_hittable'},{'reason':'no_live_match'}]}),
        dict(kind='action',executed=False,targetResolution={'reason':'query_timeout','lookups':[{'reason':'query_timeout'}]}),
        dict(kind='action',executed=True,targetResolution={'reason':'matched','lookups':[{'reason':'matched'},{'reason':'no_live_match'}]}),
        dict(kind='summary',executed=1,rejected=2)]
  result=summarize_events(rows)
  self.assertEqual(result['targetResolutionReasons'],{'no_hittable_target':1,'query_timeout':1})
  self.assertEqual(result['liveLookupReasons'],{'not_hittable':1,'no_live_match':1,'query_timeout':1})
  old=summarize_events([dict(kind='action',executed=False),dict(kind='summary',executed=0,rejected=1)])
  self.assertIsNone(old['liveLookupReasons'])
