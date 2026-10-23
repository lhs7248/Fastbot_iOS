# RN 非标准控件识别验收

## 根因与实现

原公告页的全部、未读、已读、筛选和图标是Other/StaticText，旧版只接受标准控件，最后只剩ScrollView。现将有短单行标签、原始宽度不超过屏幕、高度8–88pt的可见启用Other/StaticText作为推测候选；排除滚动条和大段正文，整行设置项可识别。重复位置只保留一个点击候选，实时查询必须匹配快照的type/id/label、原始bounds与重复数，且hittable。候选定位遍历预算为32个元素/4秒（单次XCTest远程调用不提供硬实时保证），无法确认就拒绝。

新候选不是已确认按钮。每次记录recognition、targetLabel、inferredCandidateCount、liveMatchCount，点击后用现有守卫检查效果、限制重复无效操作。

iOS 26系统候选词实际位于SystemInputAssistantView和inputView同级宿主，仅过滤Keyboard不够。捕获原生快照确认后，整段系统输入宿主、Keyboard/Key和状态栏从观察与候选中剔除。每轮前12种页面保留原生类型快照，输入值和安全输入标签继续脱敏。

页面切换会短暂只有滚动容器。耗尽必须在相同指纹连续至少3次且持续2秒才确认；NOP耗尽标记随上下文变化失效。末次XML在耗尽判断前保存，避免留错现场。两次有界恢复和拒绝盲点坐标的约束保留。

## 原受阻页重放

将20261023-125104-46bb88的last-tree.xml重建为标准化节点输入适配器，候选1→9，包含全部/未读/已读/筛选和两个图标，也包含标题和空状态文本，因此不能宣称9个都是真正按钮。此为识别规则离线验证，不是原公告页所有入口的真机业务断言。

## 最终真机

运行20261023-134953-f14ee2，新零帮-新基座，iPhone13 Pro/iOS26.6.1，source引擎，2分钟预算。XCTest Passed，stopReason=time_budget，completed=true，未以no_progress_exhausted提前终止。

- 46次操作：25点击、21滚动；27次可观测界面变化、18次无变化、最后1次效果待观察。
- 推测控件点击19次：其中12次界面变化、7次无变化。实际点击到门店、业务区域、个人信息、头像、查看大图等入口；不等同业务断言通过。
- 屏蔽20个上下文动作，恢复2次；14次拒绝（9次实时目标无法确认，5次无返回按钮）。23个内部状态，不是23个业务页面。
- 同pageKey最长连续滚动3次（原始基线32次）；同上下文/目标/方向无变化最多2次，超限0。
- 已知系统输入候选词/键点击0；保留的12份原生类型快照中SystemInputAssistantView/Keyboard/Key节点为0。
- 内存采样覆盖率80.77%，启动及恢复阶段有缺口，quality=incomplete，因此总退出码6，不能把整条采集链路记为通过。探索XCTest通过与内存采集质量分别呈现。

结果目录下report.html、test.xcresult、exploration/exploration.jsonl、summary.json、recognition-verification.json及original-blocked-page-replay-candidates.json保存证据。

## 回归

54项Python测试最终通过；树适配和守卫host测试通过；iOS签名构建成功，build.log无编译警告或错误。JS监控的一项0.8秒进程测试曾在真机并发负载下返回采集不足，单测及空闲时整组12项重跑通过，未修改检测逻辑以掩盖波动。新增测试覆盖RN标签/重复图标、完整系统输入宿主、原始尺寸防裁剪误判、全宽设置行、耗尽稳定性及上下文改变重置。

代码仅本地修改，未提交或推送。
