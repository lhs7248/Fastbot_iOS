# JS 异常日志监控

日常使用项目根目录的统一入口，默认包含监控：

```sh
cp fastbot.example.json fastbot.local.json
# 填写本地设备、App 和签名信息后：
./run-fastbot --minutes 10
```

入口会构建签名 Runner，并在设备日志流就绪后启动 Fastbot。无需修改或重新打包被测 App。日志工具 pymobiledevice3 11.40.2 缺失时会安装到项目 `.fastbot/venv`；也可通过 `--pmd` 指定已有可执行文件。手机需连接、解锁并信任电脑。

每轮结果保存在 `.fastbot/results/<运行时间>/`：

- `run-summary.json`：整轮退出码。
- `monitor/report.json`：日志流状态、目标日志条数、异常及前后文。
- `monitor/device.log`：目标进程的原始 JSON Lines，包含时间、PID、日志级别和消息。
- `monitor/fastbot.log`：测试运行日志。
- `monitor/collector.stderr.log`：采集器诊断。
- `test.xcresult`：XCTest 结果。

采集器读取设备流以确认连接已就绪，其他进程的事件只用于就绪判定，随后丢弃，不保存、不参与 JS 错误判定。目标进程名由本地配置的 `process` 指定，不能使用 bundle ID 替代。

当前识别规则：`FASTBOT_JS_ERROR` 标记、未处理 JS 异常，以及带 `js engine: hermes` 的错误。命中时停止本轮操作，继续采集两秒，并在报告中保存最多 40 条前文和 40 条后文。按 Ctrl+C 可中止运行并保留结果。

退出码：0=未观察到匹配异常；2=JS 异常；3=采集/启动失败或中止；4=没有目标日志；5=测试失败或未完成。日志为空不能判为通过。监控结果优先于 XCTest 退出码。

限制：只能识别输出到设备日志的错误；被捕获、关闭输出、隐私隐藏、仅写入私有文件或上传 APM 的异常可能遗漏。没有 source map 还原、历史日志检索或自动截图。日志可能包含业务数据，请保存在本地。

针对性测试：

```sh
python3 -m unittest discover -s tools -p 'test_run_fastbot.py'
python3 -m unittest discover -s tools/js-monitor -p 'test_*.py'
```
