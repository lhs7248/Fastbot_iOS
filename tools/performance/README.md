# iOS 内存采样与报告

## 默认入口

使用根目录 `./run-fastbot`。默认 5 秒采一次，可用 `--sample-interval` 调整（至少 0.5 秒）。`pymobiledevice3==11.40.2` 的 `developer dvt sysmon process monitor process --userspace --keep-monitoring` 保持 Instruments 数据流并跟随进程重启。只选择配置的进程名，多个匹配进程时选择最新一代；不会把同名多进程的内存相加。

采集开始于构建完成后、Fastbot 执行之前，结束于本轮测试清理时。源采样时间用于曲线和斜率，接收时间单独保存。重复、不递增、明显过期、未来或缺失时间戳不会当成新有效样本。工具断连后最多尝试两次重连，失败/缺测记录仍保留。不同重连使用不同原始输出文件，避免截断后漏读。

## 产物

- `performance/raw-metrics*.jsonl`：Instruments 原始目标进程字段。
- `performance/samples.jsonl`：标准样本，主指标 bytes；包含采集失败和缺测记录。
- `performance/memory.csv`：时间、PID、分段、状态、物理占用、驻留内存、失败原因；缺失字段留空。
- `performance/collector.log`：连接、进程重新选择等诊断。
- `performance/collector-summary.json`：采集起止、间隔、重试和终止原因。
- `performance/summary.json`：采集质量、覆盖率、最长缺口、每段基线/峰值/结束值/增长率。
- `issues.json`：测试结果、日志/内存质量、JS 异常、Fastbot 操作和 PID 重启时间线。
- `report.html`：可离线打开的报告和内嵌 SVG 曲线，不依赖网络资源。

样本字段：`timestamp` 为带时区的源时间，`elapsedSeconds` 为源时间相对采集起点，`receivedElapsedSeconds` 为读取时间；`pid`、`segmentId` 区分进程代次；`status` 为 ok/missing/error/unavailable；`metrics.physicalFootprintBytes` 与 `metrics.residentBytes` 为各自指标。缺失物理占用不能用 RSS 补位，也不能填零。

质量为 ok/incomplete/failed；增长风险为 not_configured/inconclusive/suspicious_growth/no_growth_signal。预期样本数按完整采样间隔统计，不要求起点零秒恰好有样本，不把最后不足一个间隔计为必须采到；同时检查首尾缺口、失败样本和至少三个有效点。零样本为 failed，少量样本仍不能证明内存平稳。

基线为每个进程段最前面至多五个有效点均值。增长率至少需要三个样本、跨度十秒且不少于两个间隔；有缺测或较大间隔时不跨缺口拟合。物理占用包括原生、JS、图片及其他开销，不等于 JS 堆。内存持续增长也不是泄漏证明。

默认增长阈值关闭。需要时同时传 `--memory-growth-rate`（MiB/min）与 `--memory-growth-ratio`（峰值/基线，必须大于1）。阈值仅用于本轮提示，未验证为平台通用标准。通过 JSON 配置时字段为 `memory_growth_rate`、`memory_growth_ratio`。

## 离线解析

```sh
python3 tools/performance/report.py .fastbot/results/<运行目录>
python3 -m json.tool .fastbot/results/<运行目录>/performance/summary.json
```

原始格式损坏会报错，不会静默转成通过。完整结果以 `run-summary.json` 和各采集质量共同判断；测试完成但内存不完整退出6，报告失败退出7。中止和 JS 异常不被内存状态覆盖。

尚未增加 Jetsam/原生崩溃拉取、source map、自动截图或堆快照；原生崩溃状态明确显示 unverified。运行产物和本地配置被 git 忽略，可能含业务数据，应留在本地。

## 验证

```sh
python3 -m unittest discover -s tools -p test_run_fastbot.py
python3 -m unittest discover -s tools/performance -p 'test_*.py'
python3 -m unittest discover -s tools/js-monitor -p 'test_*.py'
```
