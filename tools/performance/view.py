"""Human-readable, offline report presentation."""
import html
import json
import math
from datetime import datetime, timezone, timedelta

MIB = 1048576

def esc(value):
    return html.escape(str(value), quote=True)

def render_report(run, monitor, collector, summary, issues, rows, root):
    from_report = summary['segments']
    duration = summary['durationSeconds']
    def valid_row(r):
        t=r.get('elapsedSeconds')
        return (r.get('status') == 'ok' and type(r.get('metrics', {}).get('physicalFootprintBytes')) is int
                and r['metrics']['physicalFootprintBytes'] >= 0 and type(r.get('pid')) is int and r['pid'] > 0
                and type(r.get('segmentId')) is int and r['segmentId'] >= 0
                and type(t) in (int,float) and math.isfinite(t) and t >= 0)
    good = sorted([r for r in rows if valid_row(r)], key=lambda r:r['elapsedSeconds'])
    peak = max(good, key=lambda r:r['metrics']['physicalFootprintBytes']) if good else None
    baseline = from_report[0]['baselineBytes']/MIB if from_report else None
    errors = issues['errors']
    log_ok = issues['logQuality'] == 'ok'
    warning = summary['quality'] != 'ok' or not log_ok or issues['testOutcome'] != 'passed'
    if errors:
        title, conclusion = '发现异常', '捕获到 %d 条 JS 异常，请查看下方异常记录。' % len(errors)
    elif warning:
        title, conclusion = '数据不完整', ('本轮未捕获到 JS 异常；' if log_ok else '运行日志不足，暂时无法判断 JS 异常；') + '请结合采样覆盖率和缺失时段查看结果。'
    else:
        title, conclusion = '测试已完成', '本轮未捕获到 JS 异常。'
    if summary['risk'] == 'suspicious_growth':
        title, conclusion = '存在风险', conclusion + ' 内存增长超过配置阈值，建议进一步排查。'
    elif summary['growthThresholds'] is None:
        conclusion += ' 尚未设置内存增长阈值，本报告不判定是否泄漏。'
    exploration_state=run.get('exploration',{})
    if not errors and isinstance(exploration_state,dict) and exploration_state.get('completed') is False and exploration_state.get('stopReason') in ('no_progress_exhausted','consecutive_rejections'):
        title='探索受阻'
        conclusion='可用操作耗尽或目标持续无法执行，已停止重复操作。报告保留本轮证据；本轮没有完成计划时长，不代表稳定性测试通过。'
    if not errors and isinstance(exploration_state,dict):
        if exploration_state.get('evidenceStatus') in ('recovered_partial','unavailable'):
            title='探索记录不完整'
            conclusion='已生成失败报告，但探索记录未全部取回；请查看探索效果和导出诊断，不能将本轮记为通过。'
        elif exploration_state.get('stopReason') == 'validation_stop':
            title='主动停止验证'
            conclusion='本轮主动触发停止，以验证失败收尾；不是一次真实 JS 异常，测试按未完成记录。'
    cards = [('%s min' % format(duration/60,'.1f'),'已运行',False), (str(len(issues['actions'])),'已记录操作',False), (str(len(errors)) if log_ok or errors else '无法判断','JS 异常',log_ok and not errors), ('未采集','原生崩溃',False), ('未采集','内存终止 / OOM',False), ('%.0f%%' % (summary['coverage']*100),'内存采样覆盖',False), ('%.0f MiB'%baseline if baseline is not None else '无数据','首段内存基线',False), ('%.0f MiB'%(peak['metrics']['physicalFootprintBytes']/MIB) if peak else '无数据','内存峰值',False)]
    tiles = ''.join('<div class="tile"><strong%s>%s</strong><span>%s</span></div>' % (' class="good"' if green else '',esc(value),esc(label)) for value,label,green in cards)
    width,height,left,right,top,bottom = 1200,360,66,28,28,46
    xmax = max(duration, max([r['elapsedSeconds'] for r in good] or [1]), 1)
    ymax = max([r['metrics']['physicalFootprintBytes']/MIB for r in good] or [1])*1.15
    ymax = max(1, math.ceil(ymax/5)*5)
    x=lambda t:left+t/xmax*(width-left-right)
    y=lambda m:height-bottom-m/ymax*(height-top-bottom)
    chart=[]
    for i in range(5):
        value=ymax*i/4
        chart.append('<line x1="66" y1="%g" x2="1172" y2="%g" class="grid"/><text x="54" y="%g" text-anchor="end">%.0f</text>'%(y(value),y(value),y(value)+5,value))
    for i in range(7):
        seconds=xmax*i/6
        chart.append('<text x="%g" y="342" text-anchor="middle">%.1f</text>'%(x(seconds),seconds/60))
    chart.append('<text x="15" y="16">MiB</text><text x="1172" y="359" text-anchor="end">分钟</text>')
    if baseline is not None:
        chart.append('<line x1="66" y1="%g" x2="1172" y2="%g" stroke="#adb3bc" stroke-dasharray="5 5"/><text x="72" y="%g">首段基线 %.0f MiB</text>'%(y(baseline),y(baseline),y(baseline)-8,baseline))
    previous=None; groups=[]
    for row in sorted(rows,key=lambda r:r['elapsedSeconds'] if type(r.get('elapsedSeconds')) in (int,float) and math.isfinite(r['elapsedSeconds']) else float('inf')):
        if row not in good:
            previous=None; continue
        if previous is None or (row['pid'],row['segmentId']) != (previous['pid'],previous['segmentId']) or row['elapsedSeconds']-previous['elapsedSeconds']>summary['intervalSeconds']*1.5:
            groups.append([])
        groups[-1].append(row); previous=row
    for group in groups:
        chart.append('<polyline points="%s" fill="none" stroke="#3276df" stroke-width="2.5" stroke-linejoin="round"/>'%' '.join('%.2f,%.2f'%(x(r['elapsedSeconds']),y(r['metrics']['physicalFootprintBytes']/MIB)) for r in group))
        for r in group:
            chart.append('<circle cx="%g" cy="%g" r="3" fill="#3276df"><title>%.1f 秒 · %.1f MiB · PID %s</title></circle>'%(x(r['elapsedSeconds']),y(r['metrics']['physicalFootprintBytes']/MIB),r['elapsedSeconds'],r['metrics']['physicalFootprintBytes']/MIB,r['pid']))
    if peak:
        px=x(peak['elapsedSeconds']); py=y(peak['metrics']['physicalFootprintBytes']/MIB)
        chart.append('<circle cx="%g" cy="%g" r="5" fill="#d75d31"/><text x="%g" y="%g" text-anchor="%s" fill="#c3512b">峰值 %.0f MiB</text>'%(px,py,px-9 if px>950 else px+9,py-12,'end' if px>950 else 'start',peak['metrics']['physicalFootprintBytes']/MIB))
    def local_time(value):
        try: return datetime.fromisoformat(value.replace('Z','+00:00')).astimezone(timezone(timedelta(hours=8))).strftime('%Y-%m-%d %H:%M:%S')
        except (ValueError,TypeError,AttributeError): return '时间未知'
    error_html=''.join('<article class="error"><strong>%s · %s</strong><p>%s</p><details><summary>查看异常上下文</summary><pre>%s</pre></details></article>'%(esc(local_time(e.get('observedAt'))),esc(e.get('category','JS 异常')),esc(e.get('message','未提供异常内容')),esc(json.dumps(e,ensure_ascii=False,indent=2))) for e in errors)
    if not errors: error_html='<p class="muted">%s</p>'%('本轮未捕获到匹配的 JS 异常。' if log_ok else '运行日志不足，无法判断是否发生 JS 异常。')
    quality = '有效采样 %d / 预计 %d 个，最长未采到数据的时段为 %.1f 秒。'%(summary['validSampleCount'],summary['expectedSampleCount'],summary['maxGapSeconds'])
    if collector.get('warmupSeconds') is not None:
        quality += ' 采集预热 %.1f 秒，就绪后才启动本轮测试；底层每 %s 秒读取，按设定周期保留真实样本，进程切换额外保留边界点。' % (collector['warmupSeconds'], collector.get('sourceIntervalSeconds', '?'))
    quality += ' 曲线空白表示缺少采样，不代表内存为 0。进程切换处不连线。'
    segments=''.join('<tr><td>%s</td><td>%s</td><td>%d</td><td>%.1f</td><td>%.1f</td><td>%.1f</td></tr>'%(s['segmentId'],s['pid'],s['sampleCount'],s['baselineBytes']/MIB,s['peakBytes']/MIB,s['endBytes']/MIB) for s in from_report)
    exploration_html=''
    exploration=run.get('exploration')
    if isinstance(exploration,dict):
        def observed(key, fallback='未采集'):
            value = exploration.get(key)
            return str(value) if value is not None else fallback
        parts=['已发出操作 '+observed('executed'),
               '观测到界面变化 '+observed('progressCount'),
               '未观测到变化 '+observed('noEffectCount'),
               '已屏蔽动作 '+observed('blockedActionCount'),
               '恢复次数 '+observed('recoveries')]
        reason={'no_progress_exhausted':'候选动作耗尽，已停止重复操作',
                'consecutive_rejections':'目标持续无法执行，已停止',
                'external_js_error':'因 JS 异常停止，已保存探索现场',
                'js_error':'因 JS 异常停止，使用独立日志恢复探索记录',
                'validation_stop':'主动停止收尾验证（非真实 JS 异常）',
                'exception':'探索因异常结束，已保存最后现场',
                'evidence_write_failed':'探索证据写入失败，已停止操作',
                'evidence_unavailable':'探索证据不可用，详见导出诊断',
                'time_budget':'达到计划时长'}.get(exploration.get('stopReason'),'')
        status_text = {'complete':'探索记录已完整保存', 'recovered_partial':'探索记录部分恢复，尾部可能缺失', 'unavailable':'探索记录未取回，不能判断操作总数'}.get(exploration.get('evidenceStatus'),'')
        if status_text: parts.append(status_text)
        if exploration.get('xcresultAvailable') is False: parts.append('Xcode结果包不可用；探索记录已从独立日志恢复' if exploration.get('evidenceSource') == 'device_journal' else 'Xcode结果包不可用；独立日志也未取回')
        exploration_html='<h2>探索效果</h2><p class="note">'+esc(' · '.join(parts))+('<br>'+esc(reason) if reason else '')+'<br>界面变化不等于业务成功；没有变化也不一定是业务失败。结束前最后一次操作可能尚未观测。</p>'
    files=[]
    for name in ['performance/memory.csv','performance/summary.json','issues.json','monitor/fastbot.log','monitor/report.json','performance/samples.jsonl','run-summary.json','exploration/summary.json','exploration/exploration.jsonl','exploration/last-tree.xml','exploration/export-status.json']:
        path=root/name
        if path.exists():
            size=path.stat().st_size
            files.append('<a href="%s">%s · %s</a>'%(esc(name),esc(path.name),('%.1f MB'%(size/1000000) if size>=1000000 else '%.1f KB'%(size/1000))))
    technical=esc(json.dumps({'run':run,'collector':collector,'monitor':monitor,'summary':summary,'issues':issues},ensure_ascii=False,indent=2))
    return '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Fastbot 应用稳定性测试报告</title><style>
*{box-sizing:border-box}body{margin:0;background:#f4f5f7;color:#25282d;font:15px -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif}main{max-width:1500px;margin:28px auto;padding:32px;background:white;border:1px solid #e3e5e8;border-radius:16px}h1{font-size:23px;margin:0 0 8px}h2{font-size:20px;margin:30px 0 14px}.meta,.muted{color:#858b93;line-height:1.7}.meta{margin:0 0 24px;overflow-wrap:anywhere}.banner{background:#fff9e8;color:#a66b08;padding:19px 22px;border-radius:12px;line-height:1.8;font-weight:600}.tiles{display:grid;grid-template-columns:repeat(8,minmax(0,1fr));gap:12px;margin:22px 0 30px}.tile{background:#f8f9fa;border-radius:12px;text-align:center;padding:22px 5px}.tile strong{display:block;font-size:26px;line-height:1.4;white-space:nowrap}.tile span{display:block;color:#858b93;font-size:14px;margin-top:7px}.good{color:#38941d}.sub{color:#90959c;font-size:14px;font-weight:400;margin-left:10px}.chart{width:100%%;display:block;min-height:240px}.chart text{font-size:13px;fill:#8b9199}.chart .grid{stroke:#e8eaee}.note{background:#f8f9fb;border-radius:10px;padding:15px 18px;color:#68717d;line-height:1.8}.error{border-left:3px solid #d75d31;padding:12px 18px;background:#fff8f4;margin:12px 0}.error p{white-space:pre-wrap;overflow-wrap:anywhere}details{margin:18px 0}summary{cursor:pointer;color:#3974cf;padding:6px 0}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f6f7f9;padding:16px;font:12px/1.6 ui-monospace,monospace;max-height:500px;overflow:auto}table{width:100%%;border-collapse:collapse;font-size:14px}td,th{text-align:left;padding:12px;border-bottom:1px solid #eee}.files{display:flex;flex-wrap:wrap;gap:8px;align-items:center;border-top:1px solid #eef0f3;padding-top:20px;margin-top:28px}.files a{background:#f0f3f8;color:#3974cf;border-radius:7px;padding:7px 10px;text-decoration:none}.files a:hover{text-decoration:underline}@media(max-width:1100px){.tiles{grid-template-columns:repeat(4,1fr)}main{margin:16px;padding:24px}}@media(max-width:600px){main{margin:8px;padding:16px}.tiles{grid-template-columns:repeat(2,1fr)}h1{font-size:20px}.tile strong{font-size:24px}.chart{min-height:180px}table{font-size:12px}td,th{padding:8px 4px}}
</style></head><body><main><h1>应用稳定性测试报告</h1><p class="meta">Fastbot iOS · %s（北京时间） · %s</p><div class="banner">【%s】%s</div><section class="tiles">%s</section><h2>内存曲线<span class="sub">每 %s 秒采样 · %d 个有效点</span></h2><svg class="chart" viewBox="0 0 1200 365" role="img" aria-label="内存随运行时间变化，缺失数据和进程切换处断开">%s</svg><p class="note">%s</p>%s<h2>异常记录</h2>%s<p class="muted">原生崩溃、系统内存终止尚未采集；进程切换不等同于崩溃。</p><details><summary>查看分段内存数据（%d 段）</summary><p class="muted">基线为每段最初最多 5 个有效点的均值。内存使用 physical footprint，单位 MiB。</p><table><thead><tr><th>分段</th><th>进程 PID</th><th>采样点</th><th>基线 MiB</th><th>峰值 MiB</th><th>结束 MiB</th></tr></thead><tbody>%s</tbody></table></details><details><summary>技术详情与操作记录</summary><pre>%s</pre></details><footer class="files"><span class="muted">原始文件：</span>%s</footer></main></body></html>'''%(esc(local_time(run.get('startedAt'))),esc(run.get('bundleId',collector.get('process','未知应用'))),esc(title),esc(conclusion),tiles,esc(summary['intervalSeconds']),summary['validSampleCount'],''.join(chart),esc(quality),exploration_html,error_html,len(from_report),segments,technical,''.join(files))
