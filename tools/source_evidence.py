"""Export source-runner XCTest attachments into reviewable run evidence."""
import collections
import json
from pathlib import Path
import shutil
import subprocess


def normalize_attachments(raw, output):
    raw, output = Path(raw), Path(output)
    manifest = json.loads((raw/'manifest.json').read_text())
    events_path = None
    for test in manifest:
        for item in test.get('attachments', []):
            name = item.get('exportedFileName', '')
            if not name or Path(name).name != name:
                raise ValueError('Invalid exported attachment path')
            suggested = item.get('suggestedHumanReadableName', '')
            if suggested.startswith('source-exploration'):
                if events_path is not None:
                    raise ValueError('Multiple exploration attachments; select one run')
                events_path = raw/name
            if suggested.startswith('source-last-tree'):
                shutil.copyfile(raw/name, output/'last-tree.xml')
    if events_path is None:
        raise ValueError('Source exploration attachment missing')
    rows = [json.loads(line) for line in events_path.read_text().splitlines() if line.strip()]
    summary = summarize_events(rows)
    summary.update(evidenceSource='xcresult', evidenceStatus=('complete' if (output/'last-tree.xml').exists() or summary['executed'] == 0 else 'recovered_partial'), finalized=True,
                   snapshotAvailable=(output/'last-tree.xml').exists())
    shutil.copyfile(events_path, output/'exploration.jsonl')
    (output/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary


def summarize_events(rows):
    if any(not isinstance(r, dict) for r in rows):
        raise ValueError('Exploration records must be objects')
    finals = [r for r in rows if r.get('kind') == 'summary']
    if len(finals) != 1:
        raise ValueError('Source exploration summary missing or ambiguous')
    actions = [r for r in rows if r.get('kind') == 'action']
    executed = sum(r.get('executed') is True for r in actions)
    rejected = sum(r.get('executed') is False for r in actions)
    if (finals[0].get('executed'), finals[0].get('rejected')) != (executed, rejected):
        raise ValueError('Exploration summary and action records disagree')
    effects = collections.Counter(r.get('effect') for r in rows if r.get('kind') == 'action_effect')
    for key, effect in [('noEffectCount', 'no_observable_change'), ('progressCount', 'changed')]:
        if key in finals[0] and finals[0][key] != effects[effect]:
            raise ValueError('Exploration effect summary disagrees with observations')
    contexts = set()
    revisited = 0
    effect_rows = [r for r in rows if r.get('kind') == 'action_effect']
    streak = longest = 0
    for row in rows:
        before = row.get('beforeFingerprint')
        if isinstance(before, str) and before:
            contexts.add(before)
        if row.get('kind') != 'action_effect':
            continue
        after = row.get('afterFingerprint')
        if row.get('effect') == 'changed' and isinstance(after, str) and after:
            revisited += after in contexts
        if isinstance(after, str) and after:
            contexts.add(after)
        streak = streak + 1 if row.get('effect') == 'no_observable_change' else 0
        longest = max(longest, streak)
    rejected_actions = [r for r in actions if r.get('executed') is False]
    resolutions = [r['targetResolution'] for r in rejected_actions if isinstance(r.get('targetResolution'), dict)]
    resolution_reasons = collections.Counter(r['reason'] for r in resolutions if isinstance(r.get('reason'), str))
    lookup_reasons = collections.Counter(
        item['reason'] for r in resolutions for item in (r.get('lookups') or [])
        if isinstance(item, dict) and isinstance(item.get('reason'), str) and item['reason'] != 'matched')
    return {**finals[0],
            'targetResolutionReasons': dict(resolution_reasons) if resolutions else None,
            'liveLookupReasons': dict(lookup_reasons) if resolutions else None,
            'observedContextCount': len(contexts) if contexts else None,
            'revisitedContextTransitions': revisited if contexts else None,
            'maxConsecutiveNoEffect': longest if effect_rows else None,
            'explorationPassCount': sum(r.get('kind') == 'exploration_pass' for r in rows),
            'engine': 'android-reuseq-source', 'treeSource': 'xctest-accessibility',
            'rejectionReasons': dict(collections.Counter(r.get('reason', 'unknown') for r in actions if r.get('executed') is False)),
            'actionTypes': dict(collections.Counter(r.get('act', 'unknown') for r in actions if r.get('executed') is True))}


def recover_journal(journal, output, reason):
    journal, output = Path(journal), Path(output)
    matches = list(journal.rglob('exploration.jsonl'))
    if len(matches) != 1 or not matches[0].resolve().is_relative_to(journal.resolve()):
        raise ValueError('Device journal missing or ambiguous')
    source = matches[0]
    lines = source.read_text().splitlines(keepends=True)
    rows, truncated = [], False
    for i, line in enumerate(lines):
        if not line.strip(): continue
        try: rows.append(json.loads(line))
        except ValueError:
            if i == len(lines)-1 and not line.endswith('\n'):
                truncated = True
            else: raise ValueError('Device journal corrupted before its final record')
    if any(not isinstance(r, dict) for r in rows):
        raise ValueError('Device journal records must be objects')
    finalized = any(r.get('kind') == 'summary' for r in rows)
    if not finalized:
        actions = [r for r in rows if r.get('kind') == 'action']
        effects = collections.Counter(r.get('effect') for r in rows if r.get('kind') == 'action_effect')
        executed = sum(r.get('executed') is True for r in actions)
        rows.append({'kind':'summary', 'completed':False, 'stopReason':reason or 'interrupted',
                     'reconstructed':True, 'countsAreLowerBounds':True,
                     'executed':executed, 'rejected':sum(r.get('executed') is False for r in actions),
                     'states':None, 'blockedActionCount':None,
                     'progressCount':effects['changed'], 'noEffectCount':effects['no_observable_change'],
                     'recoveries':sum(r.get('kind') == 'recovery' for r in rows),
                     'finalOutcomePending':max(0, executed-sum(effects.values()))})
    summary = summarize_events(rows)
    summary.update(evidenceSource='device_journal',
                   evidenceStatus='complete' if finalized and not truncated else 'recovered_partial',
                   finalized=finalized, tailMayBeMissing=not finalized or truncated)
    if truncated: summary['completed'] = False
    checkpoint = source.with_name('checkpoint.json')
    try:
        if checkpoint.exists():
            checkpoint_data = json.loads(checkpoint.read_text())
            xml = checkpoint_data.get('xml')
            if not isinstance(xml, str) or not xml:
                raise ValueError('Invalid device snapshot checkpoint')
            (output/'last-tree.xml').write_text(xml)
            summary['lastSnapshot'] = {k:v for k,v in checkpoint_data.items() if k != 'xml'}
        elif source.with_name('last-tree.xml').exists():
            shutil.copyfile(source.with_name('last-tree.xml'), output/'last-tree.xml')
    except (OSError, ValueError, AttributeError) as exc:
        summary['snapshotError'] = str(exc)
        if (output/'last-tree.xml').exists(): (output/'last-tree.xml').unlink()
    summary['snapshotAvailable'] = (output/'last-tree.xml').exists()
    summary['nativeSnapshotCount'] = len(list(source.parent.glob('native-tree-*.json')))
    if summary['executed'] and not summary['snapshotAvailable']:
        summary['evidenceStatus'] = 'recovered_partial'
        summary['missingArtifacts'] = ['last-tree.xml']
    (output/'exploration.jsonl').write_text(''.join(json.dumps(r, ensure_ascii=False)+'\n' for r in rows))
    (output/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary


def export_source_evidence(results, device=None, runner_bundle='com.fastbot.local.runner.xctrunner'):
    results = Path(results)
    output = results/'exploration'
    raw, journal = output/'attachments', output/'device'
    raw.mkdir(parents=True, exist_ok=True)
    diagnostics = {}
    # Pull the per-run durable files even if XCTest's result database is damaged.
    if device:
        journal.mkdir(parents=True, exist_ok=True)
        try:
            subprocess.run(['xcrun','devicectl','device','copy','from','--device',device,
                '--domain-type','appDataContainer','--domain-identifier',runner_bundle,
                '--source','Documents/fastbot-evidence/'+results.name,
                '--destination',str(journal),'--timeout','10'], check=True, timeout=15, capture_output=True)
            diagnostics['deviceJournalCopied'] = True
        except (OSError, subprocess.SubprocessError) as exc:
            diagnostics['deviceJournalError'] = str(exc)
    try:
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(results/'test.xcresult'),
                        '--output-path', str(raw)], check=True, timeout=45, capture_output=True)
        summary = normalize_attachments(raw, output)
        if summary['evidenceStatus'] != 'complete':
            raise ValueError('XCTest attachments missing required snapshot; trying device journal')
        summary['xcresultAvailable'] = True
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        diagnostics['xcresultError'] = str(exc)
        try:
            try:
                report = json.loads((results/'monitor/report.json').read_text())
            except (OSError, ValueError):
                report = {}
            summary = recover_journal(journal, output, report.get('reason', 'interrupted'))
            summary['xcresultAvailable'] = False
        except (OSError, ValueError, KeyError, TypeError) as recovery_error:
            diagnostics['recoveryError'] = str(recovery_error)
            summary = {'engine':'android-reuseq-source', 'treeSource':'xctest-accessibility',
                       'completed':False,'executed':None,'rejected':None,'states':None,
                       'stopReason':'evidence_unavailable','evidenceStatus':'unavailable',
                       'finalized':False,'snapshotAvailable':False,'xcresultAvailable':False}
    summary['exportDiagnostics'] = diagnostics
    (output/'export-status.json').write_text(json.dumps(diagnostics, ensure_ascii=False, indent=2))
    (output/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary
