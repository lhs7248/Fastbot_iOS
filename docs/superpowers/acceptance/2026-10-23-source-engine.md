# 源码引擎替换验收（2026-10-23）

## 对象及结果

新基座 `org.reactjs.native.example.xlb.test`，现有 iPhone13 Pro。
最终完整入口运行 `.fastbot/results/20261023-113023-91c78d/`：源码构建成功，XCTest返回0；JS监测返回0，未捕获匹配异常；38次操作发出，1次BACK因无明确返回按钮被拒绝，3个内部状态。动作包含1次CLICK、20次向下滑动、17次向上滑动。

这些结果证明纯源码 Runner 可在真机采树、选路和执行，不证明业务正确，也不证明探索效率优于旧版。后半段仍主要在滚动容器，尚未验收更深业务路径与长期空转改善。

内存有效样本数/预计数及完整度以该运行的 performance/summary.json 为准。总体返回6，原因是内存采样不完整，不是源码测试失败。

## 二进制依赖检查

对 `.fastbot/source/DerivedData/Build/Products/Release-iphoneos/FastbotRunner-Runner.app/PlugIns/FastbotRunner.xctest/FastbotRunner` 执行 otool -L；仅系统库/XCTest，没有原来的三个Fastbot框架。Runner.app递归检查也没有嵌入FastbotLib.framework、fastbot_native.framework或fastbot_cv.framework。

## 审查与回归

独立审查发现并修复：上游强制启用EditText、传播父节点可点击属性、禁用节点仍生成动作，以及部分可见节点与完整实时边界比较不一致。新增实际引擎40次选择回归以及边界重定位回归，复审无新增阻塞问题。

源码core提供macOS host测试及iOS arm64归档构建。树适配器提供Foundation host测试。Python入口、证据导出、性能及JS监测测试均保留。

## 能力边界

Android ModelReusableAgent的iOS移植，不等同原二进制NStepQAgent；每轮从新模型开始，关闭时同步保存，不读取未校验的旧模型。不注入App、不使用截图推断动作、不执行shell或清数据。旧Framework仍在仓库供--engine legacy对照，但默认构建不依赖。

许可证为内部使用限制；没有提交或推送远端。
