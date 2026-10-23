## 本地源码引擎

默认运行入口现已使用源码编译的 Android ModelReusableAgent + XCTest 无障碍元素树，不再依赖三个旧 Fastbot Framework。构建、边界和许可证说明见 [源码引擎说明](docs/source-engine.md)。

```sh
./run-fastbot --engine source --minutes 10 --sample-interval 5
```

保留 `--engine legacy` 用于对照。下方 upstream 文档描述的是原有二进制版本，不能等同于新源码模式的能力。

## 内存采集与 HTML 报告

统一入口现在默认同时采集 iOS `physFootprint` 和设备可用的 `memResidentSize`，无需改被测 App 或重新打包。日志工具通过 Instruments 用户态连接读取进程信息，手机需连接并开启开发者模式。物理占用与驻留内存分别保存，不做替代。

```sh
./run-fastbot --minutes 10 --sample-interval 5
# 可选：明确设置仅用于提示的增长阈值（MiB/分钟和峰值/基线比值）
./run-fastbot --minutes 10 --memory-growth-rate 1 --memory-growth-ratio 1.3
```

每轮新增 `performance/samples.jsonl`、`performance/memory.csv`、`performance/summary.json`、`performance/collector-summary.json`、`issues.json` 和 `report.html`。内存原始值以 bytes 保存，图表以 MiB 展示，包含源时间、接收时间、PID、进程分段和缺测原因。App 重启或 PID 复用会另起分段；图表不跨缺测点连线。初始连接、App 未运行及收尾可能出现缺测，报告会如实显示。

报告将测试结果、日志质量和内存质量分别展示。没有有效内存数据、样本不足或有缺测，不会判成内存平稳。默认不启用未经验证的增长阈值；显式配置后也只给出“疑似增长”提示，不等同于泄漏证明。原生崩溃诊断尚未接入，不能通过 PID 变化断言崩溃。

新增整轮退出码：`6` 表示测试完成但内存采集不完整/失败；`7` 表示报告生成失败。原有 JS 异常、采集失败和中止退出码继续保留。HTML 和 JSON 都会展示最终退出码。采样器和子进程由本轮入口统一停止，已产生的数据保留。

可离线重新生成报告：

```sh
python3 tools/performance/report.py .fastbot/results/你的运行目录
```

完整 schema、采样质量和限制见 [内存报告说明](tools/performance/README.md)。

## 默认真机运行入口（含 JS 异常监控）

从项目根目录执行 `./run-fastbot --minutes 10`。该入口准备本地工作区、安装本地 Pod、构建签名 Runner、采集目标进程日志，并运行 Fastbot。JS 异常命中时停止测试并返回失败；日志不可用时返回无法判定，不按成功处理。

首次使用需要 Python 3.9+、CocoaPods、Xcode 和有效开发签名。若未找到 pymobiledevice3，入口会在 `.fastbot/venv` 安装固定版本的日志工具，需要联网。手机须已信任电脑并开启开发者模式。

首次先将 `fastbot.example.json` 复制为 `fastbot.local.json` 并填写设备 UDID、App bundle ID、进程名和开发团队。设备配置保存在被忽略的 `fastbot.local.json`，也可通过 `--device`、`--bundle-id`、`--process`、`--team` 覆盖。`--process` 是进程名，不是 bundle ID。`--minutes` 默认 10，`--throttle` 默认 300 毫秒。`--pmd` 可指定已有日志工具；`--dry-run` 可只检查命令。

日志、结果和构建产物保存在 `.fastbot/`，每次结果目录中包含 `run-summary.json`、`monitor/report.json`、设备日志、Fastbot 日志及 XCTest 结果。`no_js_error_observed` 只表示未命中日志特征，不保证所有 JS 异常都被捕获。

日志流建立后才启动 Fastbot，避免漏采启动阶段日志。异常命中后立即停止操作，再保留两秒后续日志以捕获堆栈。`device.log` 为按目标进程过滤的 JSON Lines。

原来的直接 `xcodebuild` 命令仍是底层入口，不会自动调用外部监控；日常验证请使用上面的统一入口。原上游说明如下。

---

## Introduction
Fastbot is a model-based testing tool for modeling GUI transitions to discover app stability problems. It combines machine learning and reinforcement learning techniques to assist discovery in a more intelligent way.
> Related: [Fastbot_Android](https://github.com/bytedance/Fastbot_Android)
 
***More detail see at [Fastbot architecture](https://mp.weixin.qq.com/s/QhzqBFZygkIS6C69__smyQ)

**update 2022.1**
* update Fastbot Revised License
* release AnyTrace, the Fastbot test management assistant: supports one-click Fastbot test start, crash analysis, etc. ([AnyTrace User Manual](https://www.volcengine.com/docs/6431/82895))


## Prepare test environment
  * `cd Fastbot-iOS && pod install --repo-update`
  * Open `Fastbot-iOS.xcworkspace`, Set `FastbotRunner` [Signing & Capabilities](./Doc/Fastbot-Xcode-Sign.png) and [Bundle ID](./Doc/Fastbot-Xcode-BundleId.png)
  * USB connected the device & trust the device, if you're using a simulator, start up the simulator
  * Open FastbotRunner network permission (unnecessary for simulator), a sample on device 00008030-001054A80C82802E：
  *   - Open [XcodeIDE run `testPingNetwork` in Tests](./Doc/Fastbot-Xcode-IDE.png) or Run command:
```shell
BUNDLEID=com.apple.Pages duration=240 throttle=300 xcodebuild test  -workspace Fastbot-iOS.xcworkspace -scheme FastbotRunner  -configuration Release  -destination 'platform=iOS,id=00008030-001804563E44802E' -only-testing:FastbotRunner/FastbotRunner/testPingNetwork
```
  *   - By tapping FastbotRunner on the device, the screen of the device would go black for about one minute. During the black screen interval, users should press the home button on the device to go back to the main screen. Wait patiently until the network setting dialog window pops up. Users should allow the pop up request in order to continue.
  *   - If "`ping network success`" appears in the console log, that means get network permission **successful**

## Run Test
  * Ensure that your application can run on the device. (Installed and trusted)
  * Environment Variables should be setted in command line or [Xcode IDE/Scheme/Test](./Doc/Fastbot-Xcode-Scheme.png)

|key|note|sample|
|--|--|--|
| BUNDLEID| Test App's Bundle ID|com.apple.Pages
|duration|Test duration,  units of minutes|300
|launchenv|Start arguments for Test APP, can be empty or key-values separated with ":" |isAutoTestUI=1:channel=AutoTest
|throttle|Throttle for operate, units of millisecond|300

 * A sample run test on device 00008030-001054A80C82802E. *if IDE scheme Env Vars changed , command Env Var would be void*: 
```shell
BUNDLEID=com.apple.Pages duration=240 throttle=300 xcodebuild test  -workspace Fastbot-iOS.xcworkspace -scheme FastbotRunner  -configuration Release  -destination 'platform=iOS,id=00008030-001804563E44802E' -only-testing:FastbotRunner/FastbotRunner/testFastbot
```

***More detail see at [中文手册](./Doc/handbook-cn.md)***


-----------
## Advanced Extension
Stub mode: Target dynamic library [`fastbot_stub`](./Fastbot-iOS/fastbot-stub/stub.m). Stub mode requires injection of fastbot_stub into the test app. The library captures GUI structure by parsing the app under test for fastbot. More customized features (eg. hook callback, cut View) can be constructed by users for additional abilities such as blocking certain view from being clicked, customized ViewControllers, etc.

*We highly appreciate any contribution from the community !!!*

**Usage**: 
After injecting fastbot_stub to app, you need：
* Uncomment code block `[fastbot_native addUIInterruptionMonitor: ...];`  in [FastbotRunner.m](./Fastbot-iOS/FastbotRunner/FastbotRunner.m#L57)
* Run the stub mode by editing [Scheme Environment Variables](./Doc/Fastbot-Xcode-Scheme.png)(9797 can be changed to another port number):

|key|sample|
|--|--|
|launchenv|stubPort=9797
|dataport|9797

-----------
## Analytics

To prioritize and improve Fastbot-iOS, FastbotRunner collects usage data and uploads it to Google Analytics. FastbotRunner collects the md5 hash of the test app's Bundle ID, this information allows us to measure the volume of usage. If they wish, users can choose to disable the Analytics by skip step `Open FastbotRunner network permission` or change FastbotRunner's `Wireless Data` to off in System Preference.

-----------
## Support
* Public technical discussion on github is preferred.
* Q&A:

    **Q**: Get Error when `pod install --repo-update`<br>
    **A**: install pod firstly `sudo gem install cocoapods -v=1.8.1`
    <br>

    **Q**: Get Error: `Assert Fail Timed out while evaluating UI query`<br>
        **A**:  Restart test or Replug USB or Change a USB line or Restart iPhone
    <br>

    **Q**: Get Error when use simulator<br>
          **A**: Change to Debug Mode in scheme setting
    <br>


    **Q**: Get unkown install Error:`com.apple.dt.MobileDeviceErrorDomain` <br>
          **A**: Check your signing certificate or Replug USB or Change a USB line or Restart iPhone  
    <br>

--------
## License
>  Copyright©2021 Bytedance
>
>  Licensed under [Fastbot Revised](./LICENSE) 

Fastbot-iOS required some features are based on or derives from projects below:
* [WebDriverAgent](https://github.com/facebook/WebDriverAgent) licensed under BSD-3-Clause


## Publications

If you use our work in your research, please kindly cite us as:

1. Lv, Zhengwei, Chao Peng, Zhao Zhang, Ting Su, Kai Liu, Ping Yang (2022). “Fastbot2: Reusable Automated Model-based GUI Testing for Android Enhanced by Reinforcement Learning”. In proceedings of the 37th IEEE/ACM International Conference on Automated Software Engineering (ASE 2022). ACM, To appear. [[pdf]](https://se-research.bytedance.com/pdf/ASE22.pdf)

```bibtex
@inproceedings{fastbot2,
  title={Fastbot2: Reusable Automated Model-based GUI Testing for Android Enhanced by Reinforcement Learning},
  author={Lv, Zhengwei and Peng, Chao and Zhang, Zhao and Su, Ting and Liu, Kai and Yang, Ping},
  booktitle={Proceedings of the 37th IEEE/ACM International Conference on Automated Software Engineering (ASE 2022)},
  year={2022}
}
```

2. Peng, Chao, Zhao Zhang, Zhengwei Lv, Ping Yang (2022). “MUBot: Learning to Test Large-Scale Commercial Android Apps like a Human”. In proceedings of the 38th International Conference on Software Maintenance and Evolution (ICSME 2022). IEEE, To appear. [[pdf]](https://se-research.bytedance.com/pdf/ICSME22B.pdf)

```bibtex
@inproceedings{mubot,
  title={MUBot: Learning to Test Large-Scale Commercial Android Apps like a Human},
  author={Peng, Chao and Zhang, Zhao and Lv, Zhengwei and Yang, Ping},
  booktitle={Proceedings of the 38th International Conference on Software Maintenance and Evolution (ICSME 2022)},
  year={2022}
}
```

3. Cai, Tianqin, Zhao Zhang, and Ping Yang. “Fastbot: A Multi-Agent Model-Based Test Generation System”. In Proceedings of the IEEE/ACM 1st International Conference on Automation of Software Test. 2020. [[pdf]](https://se-research.bytedance.com/pdf/AST20.pdf)

```bibtex
@inproceedings{fastbot,
  title={Fastbot: A Multi-Agent Model-Based Test Generation System},
  author={Cai, Tianqin and Zhang, Zhao and Yang, Ping},
  booktitle={Proceedings of the IEEE/ACM 1st International Conference on Automation of Software Test},
  pages={93--96},
  year={2020}
}
```