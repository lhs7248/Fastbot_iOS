# iOS 源码探索引擎（内部使用）

默认 `./run-fastbot` 现在使用 `--engine source`。它编译本仓库中的 C++/Objective-C/Objective-C++，不链接或嵌入原有三个 Fastbot Framework。无需修改新基座 App、无需注入 SDK、无需越狱。

## 运行

```sh
./run-fastbot --engine source --minutes 10 --sample-interval 5
```

旧二进制路径仅用于对照：

```sh
./run-fastbot --engine legacy --minutes 1
```

两种引擎使用 `.fastbot/source` 和 `.fastbot/legacy` 独立构建目录；运行证据统一在 `.fastbot/results/<run>/`。在 Xcode 中直接使用项目时，默认 Podfile 也选择 source 子规格。

## 结构

- `Fastbot-iOS/SourceEngine/core/`：从 Android 固定版本移植的 ModelReusableAgent 及依赖；PROVENANCE.md、LICENSE.txt、UPSTREAM_SHA256.json记录来源和移植差异。
- `FBSourceEngine.mm`：隔离引擎实例，输入 XML 和合成页面标识，输出 act/pos 等动作数据。
- `FBTreeAdapter.m`：把 XCTest 无障碍快照转换为引擎 XML、候选元素及稳定结构标识。内部兼容使用 android.widget.* 类型名称，不表示运行了 Android 控件。
- `FBSourceExplorer.m`：一次快照、本地递归、候选筛选、策略调用、重新定位与命中校验、原生元素操作、权限处理、时长限制与收尾。
- `tools/source_evidence.py`：从 xcresult 导出结构化审计附件，不需要读取被测 App 沙箱。

## 行为及边界

XCTest 提供的是 App 暴露的无障碍元素树，不是完整 UIView 层级；自绘或未暴露语义的控件仍可能不可操作。当前源码模式不做截图识别兜底。快照超出5000节点会拒绝使用，不会以截断树继续探索。

候选动作来自按钮、Cell、Link、Switch、输入框和滚动容器。禁用、零面积和离屏候选不生成动作；非交互容器不被当作按钮。执行前重新定位目标，核对原始边界及 hittable。部分可见控件用原始边界校验新鲜度、用裁剪边界交给模型。重复或无法唯一匹配的目标会拒绝，不直接按旧坐标乱点。

BACK 仅点击可明确识别的返回按钮；不模拟 Android 系统返回键。长按和其他未实现/不支持的引擎动作会被拒绝或转为 NOP。不会执行 shell、清除 App 数据或网络扰动。每次操作后读取下一帧无障碍快照，区分“手势已发出”和“观测到界面变化”。同一观测上下文、同一目标和方向两次无变化后，在引擎选路前屏蔽该动作；两次重复的相同状态转移也会屏蔽，限制上下往返循环。数字/计时器标签和小幅几何噪声被归一化，输入值不参与指纹。屏蔽针对具体目标，不会连带屏蔽同类合并控件中的其他可用目标。

无可用动作时最多终止并重新启动 App 两次，不清除数据，保留本轮屏蔽历史。仍无路可走会以 no_progress_exhausted 失败收尾，不靠无效滚动凑满时长。连续15次动作拒绝或10次无可用树也会失败。对未暴露内容的画布，树不变只能说明“没有可观测变化”，不能证明业务无变化；界面发生变化也不证明业务成功。

密码输入内容和所有输入框 value 不进入树；安全输入框不执行自动文本输入。普通可见 label/identifier 可出现在 XML 和上游诊断日志，按内部测试数据保管。树和结构状态不是业务覆盖率，也不是实际 UIViewController 名称。

新引擎是 Android ModelReusableAgent 源码的 iOS 适配，不是旧 NStepQAgent 的源码还原，不承诺相同行为。当前每轮从新模型开始；结束时同步保存 reuse.fbm，不加载未经校验的旧 FlatBuffers 文件。没有后台模型保存线程。此版本没有视觉兜底，也不含旧引擎的所有专家配置和系统扰动能力。

## 证据

标准日志、内存和 HTML 报告沿用原流程。源码模式新增：

- `exploration/exploration.jsonl`：每次策略选择、目标拒绝原因、操作发出结果、树节点/候选数和耗时。
- `exploration/summary.json`：操作发出数、拒绝数、界面变化/无变化数、屏蔽数、恢复次数、终止原因、动作类型、内部状态数。
- `exploration/last-tree.xml`：结束前最后一棵已脱敏树。
- `test.xcresult`：原始 XCTest 结果和附件。

如果附件导出失败，会在 run-summary.json 中保留错误，并在测试本身成功时返回7。内存覆盖不完整返回6，不能把它解释为引擎执行失败或性能正常。

## 验证

```sh
bash tools/source-engine/build-test.sh --ios
sh tools/source-tree/run.sh
sh tools/source-guard/run.sh
python3 -m unittest discover -s tools -p 'test_*.py'
python3 -m unittest discover -s tools/performance -p 'test_*.py'
python3 -m unittest discover -s tools/js-monitor -p 'test_*.py'
```

检查最终测试bundle的依赖：

```sh
otool -L .fastbot/source/DerivedData/Build/Products/Release-iphoneos/FastbotRunner-Runner.app/PlugIns/FastbotRunner.xctest/FastbotRunner
```

## 许可证

Fastbot Revised License限定内部使用并禁止第三方分发。保留来源与版权；这份移植源码和产物不能因为可编译就被当作MIT项目对外发布。当前改动没有推送远端。

### React Native 非标准控件

除标准按钮/输入框/滚动控件外，适配器将有短单行标签、可见且尺寸合理的Other/StaticText作为推测点击候选。同身份同位置的重复点击节点合并；同位置不同身份保留为目标组，实时查询完整结束且只有一个可操作身份时才执行。双层文本的实时匹配数必须与快照相符。滚动条、键盘和状态栏不作为业务探索候选。每次动作记录targetLabel、recognition（native_role/inferred_label）、inferredCandidateCount和liveMatchCount，操作后仍由防空转守卫验证界面效果。推测并不证明控件具有点击语义。

系统输入识别同时覆盖iOS 26的SystemInputAssistantView宿主（包含inputView和候选词/表情同级分支），从观察快照和引擎候选中一起排除。候选耗尽必须同一指纹连续至少3次、稳定至少2秒，才触发有界恢复/终止；引擎NOP耗尽标记随上下文变化失效。每轮保留前12种页面的原生类型快照附件，有文字定位最多32个元素/4秒、无文字定位最多256个元素/12秒，超限则拒绝，防止大量同名节点拖住操作。

### 失败收尾与独立证据

JS 异常先向 Runner 投递按 runID 隔离的停止请求，最多等待 30 秒收尾。审计日志同步到 Documents，原子检查点保存最后 XML，并保留原生快照。结果包无效时从设备独立日志恢复报告。evidenceStatus 区分 complete、recovered_partial、unavailable；缺少最终汇总时计数仅代表已保存记录，不能将缺失显示为零或通过。导出诊断见 exploration/export-status.json。

### 候选耗尽与采样时钟修复（2026-10-26）

`20261026-094157-4aa9e0` 的耗尽发生在头像大图预览：原生树只有 `1/1`，缺少返回按钮。计数文字原来被推测为可点击，返回又只支持 Button 的“返回”标签。另一个问题是同一有效跳转两次后被全程封禁，长测会逐渐丢失正常导航路径。

现在计数不作为点击候选。无文字的返回区域必须有同层居中标题、符合顶部左侧紧凑布局，并通过实时类型/标签/几何/命中与匹配数检查，才作为 `inferred_header_back` 操作。BACK 优先点击明确关闭/返回按钮，否则使用标准边缘返回；无候选且存在页码的预览上下文尝试原生应用根元素点击退出（`preview_tap`），仍受两次无变化封禁保护。推测的预览/返回语义须结合 action_effect 判断，不能将调用成功当作退出成功。

已验证有效但重复的跳转仅在本遍历轮内封禁；确认候选耗尽后 `beginNextPass` 可重新开放这些路径，记录 `exploration_pass`。无变化和实时拒绝的动作仍保留封禁，不会因新轮次复活。无可重开的路径时继续执行原有最多两次重启恢复，再失败退出。检查点同时保留完整脱敏原生树，便于复盘最终弹层。

原轮三次“未来样本”实际只领先接收时钟约 0.262、0.863、1.766 毫秒。采样器对不超过 50 毫秒的 wall/monotonic 时钟偏差，将相对时间限制到接收时间；原始 timestamp 和指标保留，样本记录 clockCorrectionSeconds、timingAdjustment，采集汇总记录校正次数、最大偏差与容差，HTML 显示校正说明。超出容差、旧样本、缺失时间及非递增时间仍报错。未使用旧值补空洞，也未将旧报告错误删掉。

真机迭代记录：`20261026-095356-523805` 证实预览下滑无效；`20261026-095834-534341` 证实快照 ordinal 路径不能可靠用作实时查询路径，因此已撤回该定位方式，保留 nativePath 仅供诊断。两轮均通过 validation_stop 完整收尾，不能计为 30 分钟验收。最终重新计时轮次为 `20261026-100043-1cb762`，结论以该轮实际结果为准。

后续长测 `20261026-100043-1cb762` 在约25分钟后于协议页耗尽，未通过30分钟验收；内存313个有效样本、覆盖100%、错误0、18次有审计的时钟校正（最大7.174毫秒）。图片预览 `preview_tap` 已实际产生界面变化。协议页另暴露：三层同尺寸 WebView 导致 targetForAction 判歧义，正文被当作点击候选，无文字返回查询达到4秒预算。新增回归覆盖同尺寸嵌套WebView只保留一个滚动候选且保持实时等价匹配数，WebView后代普通正文不再推测可点击（标准链接/按钮仍保留）。实时目标检查改用单次原生快照读取 enabled/frame，降低无文字扫描开销；仍核验匹配数量和 hittable。再次完整计时轮次：`20261026-103125-c030f5`。

`20261026-103125-c030f5` 在约18分钟因 Runner 查询 Application.hittable 抛出“Activation point invalid”提前结束，不能归因于 App 崩溃，也不能计为30分钟通过。该查询已移除：根级导航可用性只检查前台运行状态；具体控件仍保留实时快照、匹配数、bounds 和 hittable 校验。该轮227个内存有效样本、错误0，完整失败报告已保留。

### 复盘后修复（停止真机重跑，2026-10-26）

用户要求停止反复长测后，不再启动设备测试。`20261026-105108-76e766` 实际在约21分钟因搜索上下文耗尽退出，未达到30分钟；内存264点、覆盖100%、错误0，失败证据完整。

进一步修复：

- 横向短标签栏（宽高比>3且高度≤96pt）改为左右滚动；守卫在送入Android引擎前排除未声明方向，执行层再次拒绝方向不符的动作。此前宽390pt、高40pt的标签栏被反复上下滑，是无效操作的实际来源之一。
- 原生输入宿主继续脱敏裁剪，但根快照保留inputVisible布尔值参与指纹，避免键盘打开/关闭时共用封禁记录；不保存键盘文字或输入值。
- target_stale_or_not_hittable不再一次永久封禁，允许一次有限重试，第二次仍拒绝才封禁；成功执行会重置瞬态拒绝计数。结构无效目标仍立即封禁。
- beginNextPass仅在上轮后出现新上下文，且当前上下文有有效跳转可重开时才允许。没有新发现的来回切换不能反复重置旧路径；其他页面的路径也不能被当作当前困境的出口。
- 报告新增observedContextCount、revisitedContextTransitions、maxConsecutiveNoEffect、explorationPassCount，区别树变化与新增覆盖。上下文不是业务页面覆盖率。原始审计日志不修改；历史报告按原始记录离线重算诊断，失败结论保持不变。

这些变更只通过离线回归与编译验证，尚未再做真机验证；不能宣称30分钟长测通过。

### 二次复查补充

详见 `docs/2026-10-26-exploration-followup.md`。补齐了横向XML类到真实C++动作生成的映射；输入显隐排除状态栏和屏幕外宿主；无变化计数在该动作成功跳转后清零；耗尽确认绑定候选集合；滚动轴使用原始尺寸；去重优先原生按钮；深度截断的树整棵拒绝。新增完全离线的 `bash tools/source-engine/policy-test.sh` 串联原生适配器、守卫与实际C++引擎，避免各层单测通过但组合后假耗尽。本轮不运行设备。

再次复查补充：原生数字按钮标签保留语义；路径重开必须传入当次实际候选；同位置不同身份控件保留并由实时唯一命中决定执行，查询不完整时拒绝。执行与审计使用实际选中身份的元数据。详见二次复查文档的“再次复查”节。本轮仍只离线验证，不运行真机。

### 密集候选与实时校验诊断

连续拒绝保护统计的是连续没有候选筛除进展的选择：新候选的有限重试、首次封禁不会触发全局15次提前终止，重复返回已封禁动作或不支持动作仍受15次保护限制。每个同上下文/同区域动作的查找失败仍最多重试两次，耗尽后按原有稳定确认与有限恢复流程处理。

新动作日志含targetResolution、stalledRejectionCount和blockedActionCount。HTML报告将实时查询超时、匹配数不一致、不可点击等原因翻译为中文；老记录没有详细诊断时保持未知。可使用历史checkpoint做离线策略回放：`bash tools/source-engine/policy-test.sh /绝对路径/checkpoint.json`；这只模拟候选查找失败与返回动作选择，不运行真机或验证业务点击效果。
