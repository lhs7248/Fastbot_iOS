#!/usr/bin/env python3
"""Default Fastbot iOS entry: signed build, target logs, JS failure detection."""
import argparse, datetime, json, math, os, shutil, subprocess, sys, time, uuid
from pathlib import Path
from urllib.parse import urlparse, unquote

def load_settings(values):
    result={'minutes':10,'throttle':300,'sample_interval':5,'memory_growth_rate':None,'memory_growth_ratio':None,**values}
    result.setdefault('engine','source')
    if result['engine'] not in ('source','legacy'):raise ValueError('engine must be source or legacy')
    for key in ('device','bundle_id','process','team'):
        if not result.get(key):raise ValueError('Missing '+key+'; pass the CLI option or set fastbot.local.json')
    if not isinstance(result['minutes'],int) or result['minutes']<=0:raise ValueError('minutes must be a positive integer')
    if not isinstance(result['throttle'],int) or result['throttle']<0:raise ValueError('throttle must be a nonnegative integer')
    interval=result['sample_interval']
    if type(interval) not in (int,float) or not math.isfinite(interval) or interval < 0.5:raise ValueError('sample_interval must be finite and >= 0.5 seconds')
    rate, ratio = result['memory_growth_rate'], result['memory_growth_ratio']
    if (rate is None) != (ratio is None):raise ValueError('memory growth rate and ratio must be set together')
    if rate is not None:
        if type(rate) not in (int,float) or not math.isfinite(rate) or rate < 0:raise ValueError('memory_growth_rate must be finite and nonnegative')
        if type(ratio) not in (int,float) or not math.isfinite(ratio) or ratio <= 1:raise ValueError('memory_growth_ratio must be finite and > 1')
    return result

def engine_state(state, engine):
    return state / ('source' if engine == 'source' else 'legacy')


def workspace_podfile(engine):
    subspec = 'source' if engine == 'source' else 'fastbot'
    return "platform :ios, '15.0'\nproject 'Fastbot-iOS.xcodeproj'\ntarget 'FastbotRunner' do\n  pod 'fastbot', :path => './', :subspecs => ['%s']\nend\n" % subspec


def make_commands(root,state,results,settings):
    common=['-workspace','Fastbot-iOS.xcworkspace','-scheme','FastbotRunner','-configuration','Release','-destination','platform=iOS,id='+settings['device'],'-derivedDataPath',str(state/'DerivedData')]
    build=['xcodebuild','build-for-testing',*common,'DEVELOPMENT_TEAM='+settings['team'],'PRODUCT_BUNDLE_IDENTIFIER=com.fastbot.local.runner','IPHONEOS_DEPLOYMENT_TARGET=15.0','CODE_SIGN_STYLE=Automatic','CODE_SIGN_IDENTITY=Apple Development']
    test=['xcodebuild','test-without-building',*common,'-resultBundlePath',str(results/'test.xcresult'),'-only-testing:FastbotRunner/FastbotRunner/testFastbot']
    run=[sys.executable,str(root/'tools/js-monitor/monitor.py'),'--pmd',settings['pmd'],'--udid',settings['device'],'--process',settings['process'],'--seconds',str(settings['minutes']*60+180),'--out',str(results/'monitor'),'--run',*test]
    if settings.get('engine', 'source') == 'source':
        at = run.index('--run')
        run[at:at] = ['--source-run-id', results.name, '--source-runner-bundle', 'com.fastbot.local.runner.xctrunner']
    env={'BUNDLEID':settings['bundle_id'],'duration':str(settings['minutes']),'throttle':str(settings['throttle']), 'FASTBOT_RUN_ID':results.name}
    return build,run,env

def make_performance_command(root, results, settings):
    return [sys.executable, str(root/'tools/performance/collect.py'), '--pmd', settings['pmd'],
            '--udid', settings['device'], '--process', settings['process'],
            '--interval', str(settings.get('sample_interval', 5)),
            '--seconds', str(settings['minutes'] * 60 + 180),
            '--out', str(results/'performance'),
            '--ready-file', str(results/'performance/ready.json')]


def prepare_memory_target(settings, results):
    # Make the target available for DVT warmup before the measured XCTest launch.
    with (results/'performance-prelaunch.log').open('w') as log:
        subprocess.run(['xcrun', 'devicectl', 'device', 'process', 'launch',
                        '--device', settings['device'], '--terminate-existing',
                        '--json-output', str(results/'performance-target.json'), settings['bundle_id']],
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=30)

    process = json.loads((results/'performance-target.json').read_text())['result']['process']
    executable = urlparse(process.get('executable', ''))
    name = Path(unquote(executable.path)).name
    if executable.scheme != 'file' or not name or type(process.get('processIdentifier')) is not int:
        raise ValueError('Cannot resolve launched application executable')
    return name


def wait_for_performance_ready(process, path, timeout=45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            ready = json.loads(path.read_text())
            if (not ready.get('startedAt') or type(ready.get('pid')) is not int or ready['pid'] <= 0):
                raise OSError('Invalid memory readiness acknowledgement')
            return ready
        if process.poll() is not None:
            raise OSError('Memory collector exited before producing a valid target sample')
        time.sleep(.1)
    raise OSError('Memory collector did not become ready within %s seconds' % timeout)


def run_measurement(root, results, settings, run, env, cwd):
    from performance.collect import stop_child
    from performance.report import generate_report
    perf = monitor = None
    now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
    summary = {'startedAt': now(), 'platform': 'ios', 'device': settings['device'],
               'bundleId': settings['bundle_id'], 'process': settings['process'],
               'engine': settings.get('engine','source'), 'treeSource': 'xctest-accessibility' if settings.get('engine','source') == 'source' else 'legacy-visual',
               'sampleIntervalSeconds': settings['sample_interval'],
               'memoryGrowthThresholds': ({'slopeMiBPerMin':settings['memory_growth_rate'], 'peakOverBaselineRatio':settings['memory_growth_ratio']} if settings.get('memory_growth_rate') is not None else None),
               'monitorReport': str(results/'monitor/report.json'), 'results': str(results)}
    code = 1
    try:
        actual_process = prepare_memory_target(settings, results)
        if actual_process:
            summary['configuredProcess'] = settings['process']
            settings = {**settings, 'process': actual_process}
            summary['process'] = actual_process
            run = list(run)
            if '--process' in run:
                run[run.index('--process') + 1] = actual_process
        with (results/'performance-launch.log').open('w') as perf_log:
            perf = subprocess.Popen(make_performance_command(root, results, settings),
                                    stdout=perf_log, stderr=subprocess.STDOUT, start_new_session=True)
            summary['memoryReady'] = wait_for_performance_ready(perf, results/'performance/ready.json')
            monitor = subprocess.Popen(run, cwd=cwd, env=env, start_new_session=True)
            code = monitor.wait()
    except KeyboardInterrupt:
        code = 130
        summary['reason'] = 'interrupted'
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
        summary['error'] = str(exc)
    finally:
        # Every launched collector is owned by this run and cleaned up before reporting.
        stop_child(monitor, timeout=30)
        stop_child(perf, timeout=10)
        summary.update(endedAt=now(), monitorExitCode=code,
                       performanceCollectorExitCode=perf.returncode if perf else None, exitCode=code)
        if settings.get('engine') == 'source':
            from source_evidence import export_source_evidence
            try:
                summary['exploration'] = export_source_evidence(results, settings['device'])
                if code == 0 and summary['exploration'].get('evidenceStatus') != 'complete': code = 7
                summary['explorationReport'] = str(results/'exploration/summary.json')
            except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
                summary['explorationEvidenceError'] = str(exc)
                if code == 0: code = 7
                summary['exitCode'] = code
        (results/'run-summary.json').write_text(json.dumps(summary, indent=2))
        try:
            generate_report(results)
            performance = json.loads((results/'performance/summary.json').read_text())
            # A successful test with insufficient memory data is not a successful measurement.
            quality = performance.get('quality', {})
            state = quality.get('status') if isinstance(quality, dict) else quality
            if code == 0 and state != 'ok':
                code = 6
            summary.update(exitCode=code, performanceReport=str(results/'performance/summary.json'),
                           htmlReport=str(results/'report.html'))
            (results/'run-summary.json').write_text(json.dumps(summary, indent=2))
            generate_report(results)
        except (OSError, ValueError, TypeError) as exc:
            if code == 0:
                code = 7
            summary.update(exitCode=code, reportError=str(exc))
        (results/'run-summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    return code


def main():
    root=Path(__file__).resolve().parent.parent
    p=argparse.ArgumentParser(description=__doc__)
    for opt in ('device','bundle-id','process','team','pmd'):p.add_argument('--'+opt)
    p.add_argument('--minutes',type=int);p.add_argument('--throttle',type=int)
    p.add_argument('--sample-interval',type=float)
    p.add_argument('--memory-growth-rate',type=float)
    p.add_argument('--memory-growth-ratio',type=float)
    p.add_argument('--engine',choices=['source','legacy'])
    p.add_argument('--dry-run',action='store_true',help='Print resolved commands without changing files or devices')
    a=p.parse_args();config=root/'fastbot.local.json'
    try:
        values=json.loads(config.read_text()) if config.exists() else {}
        values.update({k:v for k,v in vars(a).items() if v is not None and k!='dry_run'})
        settings=load_settings(values)
    except (ValueError,OSError) as e:p.error(str(e))
    state=root/'.fastbot';build_state=engine_state(state,settings['engine']);workspace=build_state/'workspace'
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]
    results=state/'results'/stamp
    settings['pmd']=settings.get('pmd') or shutil.which('pymobiledevice3') or str(state/'venv/bin/pymobiledevice3')
    build,run,extra_env=make_commands(root,build_state,results,settings)
    if a.dry_run:
        print(json.dumps({'cwd':str(workspace),'build':build,'run':run,'environment':extra_env,'performance':make_performance_command(root,results,settings)},indent=2));return 0
    results.mkdir(parents=True)
    print('Results: '+str(results),flush=True)
    def execute(command,log,**kwargs):
        print('Stage: '+log.name,flush=True)
        with log.open('w') as f:
            code=subprocess.call(command,stdout=f,stderr=subprocess.STDOUT,**kwargs)
        if code:raise RuntimeError(str(log)+' (exit '+str(code)+')')
    try:
        # Serialize builds and device use by this entry point.
        import fcntl
        lock=(state/'run.lock').open('w')
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if not Path(settings['pmd']).is_file():
            if a.pmd or values.get('pmd'):raise RuntimeError('Configured pymobiledevice3 executable does not exist')
            execute([sys.executable,'-m','venv',str(state/'venv')],results/'setup-venv.log')
            execute([str(state/'venv/bin/pip'),'install','pymobiledevice3==11.40.2'],results/'setup-dependencies.log')
        # A local-only workspace excludes the optional injected stub and its remote dependencies.
        shutil.copytree(root/'Fastbot-iOS',workspace,dirs_exist_ok=True,ignore=shutil.ignore_patterns('Pods','build','*.xcworkspace','*.xcuserdatad','xcuserdata'))
        (workspace/'Podfile').write_text(workspace_podfile(settings['engine']))
        shutil.copy2(root/'LICENSE',build_state/'LICENSE')
        execute(['pod','install','--no-repo-update'],results/'pods.log',cwd=workspace)
        env={**os.environ,**extra_env}
        execute(build,results/'build.log',cwd=workspace,env=env)
        # Collect performance before the log monitor starts Fastbot and launches the target.
        return run_measurement(root, results, settings, run, env, workspace)
    except (OSError,RuntimeError) as e:
        (results/'run-summary.json').write_text(json.dumps({'exitCode':1,'error':str(e)}))
        print('Fastbot failed: '+str(e),file=sys.stderr);return 1
    except KeyboardInterrupt:
        print('Fastbot interrupted; check device state.',file=sys.stderr);return 130
if __name__=='__main__':raise SystemExit(main())
