#!/usr/bin/env python3
"""Default Fastbot iOS entry: signed build, target logs, JS failure detection."""
import argparse, datetime, json, os, shutil, subprocess, sys, uuid
from pathlib import Path

def load_settings(values):
    result={'minutes':10,'throttle':300,**values}
    for key in ('device','bundle_id','process','team'):
        if not result.get(key):raise ValueError('Missing '+key+'; pass the CLI option or set fastbot.local.json')
    if not isinstance(result['minutes'],int) or result['minutes']<=0:raise ValueError('minutes must be a positive integer')
    if not isinstance(result['throttle'],int) or result['throttle']<0:raise ValueError('throttle must be a nonnegative integer')
    return result

def make_commands(root,state,results,settings):
    common=['-workspace','Fastbot-iOS.xcworkspace','-scheme','FastbotRunner','-configuration','Release','-destination','platform=iOS,id='+settings['device'],'-derivedDataPath',str(state/'DerivedData')]
    build=['xcodebuild','build-for-testing',*common,'DEVELOPMENT_TEAM='+settings['team'],'PRODUCT_BUNDLE_IDENTIFIER=com.fastbot.local.runner','IPHONEOS_DEPLOYMENT_TARGET=15.0','CODE_SIGN_STYLE=Automatic','CODE_SIGN_IDENTITY=Apple Development']
    test=['xcodebuild','test-without-building',*common,'-resultBundlePath',str(results/'test.xcresult'),'-only-testing:FastbotRunner/FastbotRunner/testFastbot']
    run=[sys.executable,str(root/'tools/js-monitor/monitor.py'),'--pmd',settings['pmd'],'--udid',settings['device'],'--process',settings['process'],'--seconds',str(settings['minutes']*60+180),'--out',str(results/'monitor'),'--run',*test]
    env={'BUNDLEID':settings['bundle_id'],'duration':str(settings['minutes']),'throttle':str(settings['throttle'])}
    return build,run,env

def main():
    root=Path(__file__).resolve().parent.parent
    p=argparse.ArgumentParser(description=__doc__)
    for opt in ('device','bundle-id','process','team','pmd'):p.add_argument('--'+opt)
    p.add_argument('--minutes',type=int);p.add_argument('--throttle',type=int)
    p.add_argument('--dry-run',action='store_true',help='Print resolved commands without changing files or devices')
    a=p.parse_args();config=root/'fastbot.local.json'
    try:
        values=json.loads(config.read_text()) if config.exists() else {}
        values.update({k:v for k,v in vars(a).items() if v is not None and k!='dry_run'})
        settings=load_settings(values)
    except (ValueError,OSError) as e:p.error(str(e))
    state=root/'.fastbot';workspace=state/'workspace'
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]
    results=state/'results'/stamp
    settings['pmd']=settings.get('pmd') or shutil.which('pymobiledevice3') or str(state/'venv/bin/pymobiledevice3')
    build,run,extra_env=make_commands(root,state,results,settings)
    if a.dry_run:
        print(json.dumps({'cwd':str(workspace),'build':build,'run':run,'environment':extra_env},indent=2));return 0
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
        (workspace/'Podfile').write_text("platform :ios, '15.0'\nproject 'Fastbot-iOS.xcodeproj'\ntarget 'FastbotRunner' do\n  pod 'fastbot', :path => './', :subspecs => ['fastbot']\nend\n")
        shutil.copy2(root/'LICENSE',state/'LICENSE')
        execute(['pod','install','--no-repo-update'],results/'pods.log',cwd=workspace)
        env={**os.environ,**extra_env}
        execute(build,results/'build.log',cwd=workspace,env=env)
        # The monitor establishes the device stream before Fastbot launches the target.
        code=subprocess.call(run,cwd=workspace,env=env)
        summary={'exitCode':code,'monitorReport':str(results/'monitor/report.json'),'results':str(results)}
        (results/'run-summary.json').write_text(json.dumps(summary,indent=2))
        print(json.dumps(summary,ensure_ascii=False),flush=True);return code
    except (OSError,RuntimeError) as e:
        (results/'run-summary.json').write_text(json.dumps({'exitCode':1,'error':str(e)}))
        print('Fastbot failed: '+str(e),file=sys.stderr);return 1
    except KeyboardInterrupt:
        print('Fastbot interrupted; check device state.',file=sys.stderr);return 130
if __name__=='__main__':raise SystemExit(main())
