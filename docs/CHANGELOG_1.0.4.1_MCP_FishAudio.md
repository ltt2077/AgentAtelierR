# AgentAtelierR 1.0.4.1 MCP FishAudio

Android 与 Windows 同步更新，GitHub 标签为 `v1.0.4.1`。应用内展示版本为 **1.0.4.1 MCP FishAudio**，Android 系统版本名为 `1.0.4.1`、内部版本代码 `45`。Flutter 工程保留合法的三段版本 `1.0.4+45`；Windows 版本字符串为 `1.0.4.1`，数值文件版本为 `1.0.4.45`。

## 本版更新

- 新增独立的 Fish Audio MCP（OAuth）语音服务，使用官方登录、PKCE 授权及工具探测。普通对话与持续 ASMR 共用现有播放流程，原有 Fish Audio API 配置继续单独保留。
- MCP 模型改为下拉选择，列出 `s2.1-pro-free`、`s2.1-pro`、`drama-3`，同时保留“服务默认（不指定模型）”及已经保存的自定义模型值。选择不会被静默替换；本页修改为草稿，点击“保存并使用 MCP”后下次请求才生效，返回或取消不会保存。
- MCP 普通音色与 ASMR 音色独立配置并跟随设置备份保存；ASMR 留空时沿用普通音色。科洛蒂娅固定音色 `7b7667d545f94326a7089830d2b55261` 在页面只读显示，仅在她有实际台词时调用；选用 MCP 时复用该连接和所选模型，不依赖 REST API Key。
- 取消客户端的 inputSchema 拒绝校验，按用户要求保留模型透传，未声明模型字段时使用 `model`。最新真实 MCP schema 只有 `text`、`voice_id`、`language`，且 `additionalProperties: false`，公开契约没有模型切换字段；下拉与透传不代表云端接受或采用。已明确启用的 REST 回退使用现有 API Key 和音色，继续沿用明确选择的 MCP 模型；只有 MCP 选择“服务默认”时才使用原 API 模型配置。
- 修复 MCP 错误只显示 `StateError`、无法定位原因的问题：保留错误阶段、错误码、message、可用的 HTTP 状态与 request ID，设置中可查看完整 schema 并复制脱敏诊断。
- 修复工具误选、分页遗漏和多种音频返回格式漏解析；支持内嵌音频、资源链接、Markdown 音频链接、嵌套及非对象 JSON，按实际音频格式保存后缀。
- 修正 MCP 与 REST 回退的日志来源。REST 回退默认关闭并保留用户此前保存的开关；生成已经提交后，不因超时、结果或音频处理失败自动再次生成或换服务，避免重复调用。
- 新增最近请求模型、云端返回模型及调用状态，区分草稿、已提交请求与云端响应。未返回模型标识时明确显示无法确认切换；草稿与最近请求不同时，提示最近记录仍属于旧设置。
- 返回模型诊断优先读取明确的 `actual_model`、`used_model`，再读取普通模型元数据，避免外层的模型回显覆盖实际使用模型字段。并发调用按提交顺序保护最近记录，较早响应或失败不会覆盖较新调用的模型证据。
- 完善连接取消与工具重新探测，丢弃断开后的晚到音频，避免沿用失败探测的旧工具。
- Windows 同步全部 Flutter 修改，并将浏览器 OAuth 回调转交给已经运行的应用实例，使回调能够使用原进程的 PKCE 状态。

## 使用方法

打开“设置 → TTS → Fish Audio MCP（OAuth）”，登录官方账号并探测工具，完成后选择模型、音色并保存。模型留空表示由服务决定。遇到问题时在该页面复制脱敏诊断，无需反复生成语音。

MCP 和 Fish Audio REST 使用不同授权与计费路径。MCP 具体可用模型、套餐积分和账号权益以官方服务实际返回为准。较早的 HTTP 402 日志来自 REST 回退；用户最新提供的 00:30、00:31 两次调用均记录 `actualProvider=Fish Audio MCP`，不能归咎于 REST。用户随后提供的真实 `text_to_speech` schema 已确认只有文本、音色和默认音色语言选择，不包含模型切换字段；`language` 仅在未指定 `voice_id` 时选默认音色。网页记录仍显示 S2.1 Pro，不能仅凭客户端透传、下拉选择或音频成功断言后台已切换。额外模型参数是被拒绝、忽略还是另行处理，仍待官方或实际响应证据确认。

详细说明见 [Fish Audio MCP 接入与诊断](fish_mcp_integration.md)。

## 构建与验证

两端 release 必须使用 `tool/build_protected.ps1` 的正常 main 入口，启用角色资源加密、私有 PC Agent 配置保护、Dart 混淆与分离调试符号。Windows ZIP 应包含 EXE、DLL 与完整 `data`，解压后运行 `AgentAtelierR.exe`，不要只复制 EXE。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tool\build_protected.ps1 -Target apk -Mode release
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tool\build_protected.ps1 -Target windows -Mode release
```

依赖已缓存时可追加 `-Offline`，本轮两端构建使用此参数；它仅改变依赖获取方式，角色资源加密、私有配置保护与 release 混淆照常执行。

- 本轮完整测试 1375 项通过、61 项跳过，包含 107 项 MCP 协议、运行时、配置及设置测试；完整 `flutter analyze --no-pub` 无问题。
- 已将用户提供的真实 `text_to_speech` schema 保存为回归测试夹具，验证没有模型字段时仍可保存和透传所选值，并明确提示云端未承诺切换；音频返回不冒充模型验收。
- Android 与 Windows 均已通过受保护脚本完成正常 main 入口的 release 构建，资源加密与 Dart 混淆参数已启用。
- Android：`1.0.4.1` / `45`，非 debug，三种 ABI 均为 AOT，无 kernel 调试快照；APK v2 签名与 ZIP CRC 检查通过。为支持现有测试设备覆盖安装，沿用现有 Android Debug 证书签名，构建模式仍为 release。
- 两端均包含 7 个加密角色包和 7 个加密预览，文件头为 `AARENCR1`；未发现已知明文角色源、独立密钥或私有联动配置文件。Windows 包含完整 1596 个运行文件，含 OAuth、音频及安全存储所需插件。
- Android 构建器仍输出 ELF DWARF 信息提示；已启用混淆不代表所有原生调试信息均已剥离。

本地模拟测试不代表真实账号生成、扣费或试听验收。本轮代码验证没有触发付费语音生成，没有安装或启动客户端；真实云端模型选择、Windows OAuth 回调、Team 权益与听感仍未完成验收。

## 发布附件

- Android：`AgentAtelierR-1.0.4.1-MCP-FishAudio-release.apk`
- Windows：`AgentAtelierR-1.0.4.1-MCP-FishAudio-windows-release.zip`

本次新构建产物：

| 附件 | 大小（bytes） | SHA-256 |
| --- | ---: | --- |
| Android APK | 647143847 | `5f17ad7de7ed969e299a47d6b0a90346f62965522ee9b49569a5d5b748acc8ca` |
| Windows ZIP | 598991238 | `765ce26936e3895b24d1ecc8a2f0bf61fda8cacf370cc9a3ced58f396245c4a9` |

本地产物路径分别为 `build/app/outputs/flutter-apk/app-release.apk` 和 `build/releases/AgentAtelierR-1.0.4.1-MCP-FishAudio-windows-release.zip`。本地构建、测试与包体报告保存在 `build/reports/`，不上传原始资源或调试符号。

原始服装、苏菲立绘、密钥、私有联动服务器配置和 OAuth 凭据不提交源码仓库。安装包包含本地构建所需资源；Android 沿用现有签名以支持覆盖测试安装。
