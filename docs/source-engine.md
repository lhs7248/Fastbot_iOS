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

除标准按钮/输入框/滚动控件外，适配器将有短单行标签、可见且尺寸合理的Other/StaticText作为推测点击候选。同位置仅保留一个点击候选，双层文本的实时匹配数必须与快照相符。滚动条、键盘和状态栏不作为业务探索候选。每次动作记录targetLabel、recognition（native_role/inferred_label）、inferredCandidateCount和liveMatchCount，操作后仍由防空转守卫验证界面效果。推测并不证明控件具有点击语义。

系统输入识别同时覆盖iOS 26的SystemInputAssistantView宿主（包含inputView和候选词/表情同级分支），从观察快照和引擎候选中一起排除。候选耗尽必须同一指纹连续至少3次、稳定至少2秒，才触发有界恢复/终止；引擎NOP耗尽标记随上下文变化失效。每轮保留前12种页面的原生类型快照附件，定位超32个元素或4秒预算则拒绝，防止大量同名节点拖住操作。

### 失败收尾与独立证据

JS 异常先向 Runner 投递按 runID 隔离的停止请求，最多等待 30 秒收尾。审计日志同步到 Documents，原子检查点保存最后 XML，并保留原生快照。结果包无效时从设备独立日志恢复报告。evidenceStatus 区分 complete、recovered_partial、unavailable；缺少最终汇总时计数仅代表已保存记录，不能将缺失显示为零或通过。导出诊断见 exploration/export-status.json。
