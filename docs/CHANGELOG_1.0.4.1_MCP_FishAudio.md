# AgentAtelierR 1.0.4.1 MCP FishAudio

Android 与 Windows 同步更新，GitHub 标签为 `v1.0.4.1`。应用内展示版本为 **1.0.4.1 MCP FishAudio**，Android 系统版本名为 `1.0.4.1`、内部版本代码 `45`。Flutter 工程保留合法的三段版本 `1.0.4+45`；Windows 版本字符串为 `1.0.4.1`，数值文件版本为 `1.0.4.45`。

## 本版更新

- 新增独立的 Fish Audio MCP（OAuth）语音服务，使用官方登录、PKCE 授权及工具探测。普通对话与持续 ASMR 共用现有播放流程，原有 Fish Audio API 配置继续单独保留。
- MCP 模型改为下拉选择，列出 `s2.1-pro-free`、`s2.1-pro`、`drama-3`，同时保留“服务默认（不指定模型）”及已经保存的自定义模型值。选择不会被静默替换。
- MCP 普通音色与 ASMR 音色独立配置并跟随设置备份保存；ASMR 留空时沿用普通音色。科洛蒂娅固定音色 `7b7667d545f94326a7089830d2b55261` 在页面只读显示，仅在她有实际台词时调用；选用 MCP 时复用该连接和所选模型，不依赖 REST API Key。
- 取消客户端的 inputSchema 拒绝校验，模型原样发送至云端决定可用性；工具未列出模型字段或枚举时同样允许请求。优先沿用工具声明的参数名，未声明模型字段时使用 `model`。已明确启用的 REST 回退继续使用独立的 API 模型与音色配置。
- 修复 MCP 错误只显示 `StateError`、无法定位原因的问题：保留错误阶段、错误码、message、可用的 HTTP 状态与 request ID，设置中可查看完整 schema 并复制脱敏诊断。
- 修复工具误选、分页遗漏和多种音频返回格式漏解析；支持内嵌音频、资源链接、Markdown 音频链接、嵌套及非对象 JSON，按实际音频格式保存后缀。
- 修正 MCP 与 REST 回退的日志来源。REST 回退默认关闭并保留用户此前保存的开关；生成已经提交后，不因超时、结果或音频处理失败自动再次生成或换服务，避免重复调用。
- 完善连接取消与工具重新探测，丢弃断开后的晚到音频，避免沿用失败探测的旧工具。
- Windows 同步全部 Flutter 修改，并将浏览器 OAuth 回调转交给已经运行的应用实例，使回调能够使用原进程的 PKCE 状态。

## 使用方法

打开“设置 → TTS → Fish Audio MCP（OAuth）”，登录官方账号并探测工具，完成后选择模型、音色并保存。模型留空表示由服务决定。遇到问题时在该页面复制脱敏诊断，无需反复生成语音。

MCP 和 Fish Audio REST 使用不同授权与计费路径。MCP 具体可用模型、套餐积分和账号权益以官方服务实际返回为准。本地日志中曾出现的 HTTP 402 来自 REST 回退，不能据此认定 MCP 返回 402；旧日志缺少 MCP 原始错误，历史触发点没有得到真实生成验证。

详细说明见 [Fish Audio MCP 接入与诊断](fish_mcp_integration.md)。

## 构建与验证

两端均使用 `tool/build_protected.ps1` 的正常 main 入口生成 release，启用角色资源加密、私有 PC Agent 配置保护、Dart 混淆与分离调试符号。Windows ZIP 包含 EXE、DLL 与完整 `data`，解压后运行 `AgentAtelierR.exe`，不要只复制 EXE。

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tool\build_protected.ps1 -Target apk -Mode release
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tool\build_protected.ps1 -Target windows -Mode release
```

- 最终 Flutter 全量测试 **1351 项通过、61 项按环境条件跳过**；静态检查无问题。包含 8 项 MCP 设置页、7 项音色配置持久化测试，以及模型透传、音频结果、断开竞态、重复生成保护和既有聊天/ASMR 回归。
- Android 与 Windows release 均构建成功。Android 元数据为 `versionName=1.0.4.1`、`versionCode=45`、非 debuggable，三种 ABI 均包含 AOT，APK v2 签名验证通过。
- Windows 文件/产品版本字符串为 `1.0.4.1`，数值版本为 `1.0.4.45`，`IsDebug=false`。ZIP 包含完整运行目录的 1596 个文件，含 MCP 回调及安全存储插件。
- 两端归档 CRC 均通过，各含 7 个加密角色包和 7 个加密预览，文件头均为 `AARENCR1`；未包含明文莱莎角色源文件、独立密钥或私有配置文件。

本地模拟测试不代表真实账号生成、扣费或试听验收。本轮没有触发付费语音生成，没有重新安装或启动客户端；Windows 的真实 OAuth 回调、Team 权益、在线模型和听感仍未在本版进行验证。

## 发布附件

- Android：`AgentAtelierR-1.0.4.1-MCP-FishAudio-release.apk`
- Windows：`AgentAtelierR-1.0.4.1-MCP-FishAudio-windows-release.zip`

| 附件 | 大小（字节） | SHA-256 |
| --- | ---: | --- |
| `AgentAtelierR-1.0.4.1-MCP-FishAudio-release.apk` | 647,135,447 | `c725d398a8d161947422b32aec17a309d822ee55f6a154b25a280239945c6cfc` |
| `AgentAtelierR-1.0.4.1-MCP-FishAudio-windows-release.zip` | 598,984,529 | `80e273cf391b19eb44e1e18b5d76924ed20b8e4ac09a3044c686f03122382799` |

本地产物分别位于 `build/app/outputs/flutter-apk/app-release.apk` 和 `build/releases/AgentAtelierR-1.0.4.1-MCP-FishAudio-windows-release.zip`。

原始服装、苏菲立绘、密钥、私有联动服务器配置和 OAuth 凭据不提交源码仓库。安装包包含本地构建所需资源；Android 沿用现有签名以支持覆盖测试安装。
