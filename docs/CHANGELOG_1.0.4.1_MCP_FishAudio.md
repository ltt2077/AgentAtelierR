# AgentAtelierR 1.0.4.1 MCP FishAudio

## 更新内容

- Android、Windows 同步更新 Fish Audio MCP，支持官方账号登录和语音合成。
- 增加模型选择：`s2.1-pro-free`、`s2.1-pro`、`drama-3`。指定模型通过 Story Studio 的后端配置生成；选择“服务默认”使用普通 TTS。
- 普通模式、ASMR 可分别设置音色，科洛蒂娅沿用应用内置音色。
- 修复 Studio 配置和生成结果解析，增加等待结果时的只读查询，避免失败后自动重复生成。
- 完善错误诊断，并修复 Windows 浏览器授权回调。

## 使用方法

1. Android 安装 APK；Windows 解压完整 ZIP 后运行 `AgentAtelierR.exe`。
2. 打开“设置 → TTS → Fish Audio MCP（OAuth）”，登录 Fish Audio 并读取工具列表。
3. 选择模型，填写普通/ASMR 音色 ID，点击“保存并使用 MCP”。ASMR 音色留空时沿用普通音色。
4. 遇到问题时，在 MCP 设置页复制脱敏诊断，避免反复点击生成。

指定模型使用 Studio 云端项目，会保存台词和生成音频。可用模型与积分以 Fish Audio 账号权益为准；项目后端配置不等于实际推理模型已独立验证。
