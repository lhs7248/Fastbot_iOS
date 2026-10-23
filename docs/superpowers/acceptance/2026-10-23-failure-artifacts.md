# 异常中止后的报告与探索附件验收

## 根因和修复

原监控器发现 JS 异常后立即终止 xcodebuild，Runner 附件写入和结果包封口尚未结束，xcresulttool 返回 64。

现在 source 模式先投递带 runID 的停止请求，默认等待 30 秒协作收尾，失败或超时才强制停止，JS 异常仍按退出码 2 判失败。Runner 持续同步审计日志、原子保存最后 XML 检查点，并独立保留最多 12 份原生快照。主机同时取回独立文件和 XCTest 附件；结果包不可用时自动恢复报告。

证据状态区分 complete、recovered_partial 和 unavailable。强杀后没有最终汇总时，只汇总已保存记录，明确计数是下限、尾部可能缺失。快照单独损坏不会丢弃可信动作日志；中段日志损坏不静默略过。无法承诺恢复尚未落盘的数据，报告会明确限制。

Scheme 显式传递 FASTBOT_RUN_ID；首次真机发现普通进程环境变量不会自动进入 Runner，已补回归并确认生成的 xctestrun 包含本轮标识。只取本轮目录，不混用其他运行数据。

## 真机验证

常规运行 20261023-172142-77bb82 完成两分钟，主附件完整，内存 28 个有效点、零缺失、覆盖 100%。该轮发现 runID 透传问题，不用它证明备用通道。

修正后运行 20261023-172454-23bc9c，主动投递 validation_stop，验证失败收尾，不伪造 App JS 异常。Runner 正常响应，XCTest 明确失败，整体退出码 5。30 个已执行操作、6 个拒绝、21 次界面变化、9 次无变化、8 个屏蔽动作，末次效果待观察 0。completed=false，stopReason=validation_stop，evidenceStatus=complete。结果包可导出，独立日志成功取回，最后 XML 与 12 份原生快照保留。内存 18 个有效点，错误/缺失 0，覆盖 100%。

在同轮 recovery-validation/<runID> 子目录中不提供 xcresult，仅从设备独立日志恢复生成 HTML。evidenceSource=device_journal、evidenceStatus=complete、xcresultAvailable=false。事件内容和顺序、全部计数、最后 XML 与主附件一致，原生快照 12 份。JSON 重新排版导致字节 SHA 不同，但解析后的全部事件与规范化 SHA 一致。原始结果包保留。

证据：exploration/recovery-verification.json、exploration/export-status.json、exploration/device/、report.html 和 recovery-validation/<runID>/report.html。恢复报告复用同一轮真实数据，不是另一轮业务运行。

## 回归与结论边界

24 项入口/证据测试、38 项性能/报告测试、15 项 JS 监控测试通过。覆盖协作收尾等待、超时强制停止、路径校验、截断尾行、中段损坏、缺少监控报告、快照损坏和 runID 传递。iOS 签名构建成功。

本次真机验证采用主动停止；真实 JS 错误触发的监控分支由进程级集成测试覆盖，没有声称本轮再次发现真实 JS 崩溃。complete 表示已产出的探索记录与最后快照已保全，不代表业务遍历或稳定性测试通过。

代码仅本地修改，未提交或推送。
