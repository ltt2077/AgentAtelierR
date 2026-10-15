# Fish Audio MCP 接入与 StateError 诊断

本次加入了独立的 Fish Audio MCP TTS Provider。原有 Fish Audio REST、百炼、通用 OpenAI TTS、MiMo 和本地 CosyVoice 仍然保留；MCP 不会进入 LLM 请求链，也不会覆盖普通 API Key。

## 已实现

- 使用 `mcp_dart 2.4.3` 连接 `https://api.fish.audio/mcp` 的 Streamable HTTP。
- 新增 `Fish Audio MCP（OAuth）` TTS Provider，聊天和持续 ASMR 共用现有音频缓存、响度均衡、立体声和 Spine 播放流程。
- 使用 Fish Audio OAuth Authorization Code + PKCE（S256）。首次点击设置页的“登录并探测 tools/list”时才进行动态客户端注册和浏览器授权。
- OAuth access token、refresh token、有效期和客户端 ID 使用独立的安全存储命名空间；普通 API 服务导出不会包含这些内容。
- 授权回调使用 `fishmcp://oauth/callback`。Android 已配置 intent-filter，Windows 使用 `app_links` 的同一自定义 scheme；Windows 启动时会在当前用户注册 `fishmcp` URL 协议。
- 授权后先执行 `tools/list`，保存工具名、描述和完整 input schema；未完成工具探测时，生成请求会被阻止。
- 根据真实 schema 只发送已声明的字段（文本、音色、模型、语言、格式、语速），避免把普通 REST 参数盲传给 MCP。
- 支持 MCP 返回的内嵌音频，以及 `https://*.fish.audio` 音频 URL；拒绝非 HTTPS 或非 Fish Audio 域名。
- MCP 连接失败不会自动删除现有 Fish REST 配置。设置页保留 MCP 失败回退开关字段，原有 Provider 可随时切回。
- MCP 模型提供下拉选择：`s2.1-pro-free`、`s2.1-pro`、`drama-3`，兼容已保存的自定义值；“服务默认”不指定模型。实际 MCP 能力仍由 tools/list 校验，固定选项不代表服务支持全部模型。

## 2026-10-15 StateError 修复

旧实现把工具错误、未找到音频、下载失败等多种情况包装为 `StateError`，而回退日志只记录异常类型，导致真实原因丢失。现在保留错误的 `stage`、`code`、`message`、可用的 HTTP status 和 request ID，设置页可以复制脱敏诊断和完整工具 inputSchema。

- 优先选择真正的 `text_to_speech`，排除搜索、余额等说明中提到 TTS 的非生成工具；支持工具分页，重新发现失败时禁用旧工具。
- 按真实 schema 校验参数、必填项和枚举，语言随角色设置映射；不支持的模型值会在提交生成前明确报错，设置页提供清空旧值的按钮。
- 解析 AudioContent、ResourceLink、EmbeddedResource、Markdown 链接、嵌套 JSON，以及数组或字符串形式的 structuredContent；按实际音频容器保存文件后缀。
- 下载不携带 OAuth 凭据，逐次验证 HTTPS 重定向，限制超时和文件大小。未知外部 CDN 明确报域名错误，不自动信任所有主机。
- 设置页实时反映异步 OAuth / 连接状态，断开后丢弃晚到结果；日志区分选择的 provider 与实际使用的 provider。
- REST 回退默认关闭，保留用户以前明确保存的开关值。开启时，仅在本地准备或参数校验失败、尚未提交 MCP 生成时允许回退；提交后结果未知、工具报错、下载或音频校验失败均不自动回退或再次生成。

已从设备 `a43d2d7a` 的已有日志确认：`MCP StateError → REST 回退 → POST /v1/tts → HTTP 402`。402 的 message 为 `Insufficient API credit. API credit is managed independently from platform credit.`，来自 REST。用户已说明模型设置用于测试回退，当前问题聚焦 MCP StateError。旧日志缺少 MCP 原始错误与实际 schema，不能追溯出那次失败的唯一原因，也不能据此认定 Plus 会员无权益、Team 不一致或 MCP 计费异常。

本地脱敏证据：`build/diagnostics/fish-mcp-readonly-20261015/evidence.redacted.json`。当前 Team、Workspace、余额和套餐权益尚未取得经过鉴权的实际查询结果。官方说明 MCP 使用套餐积分，和 developer API credit 区分；`get_credit_balance` 是免费查询工具，但本轮没有已授权的工具通道执行它，不能把公开文档当作本账号的查询结果。

诊断保存在应用临时目录 `fish_mcp_diagnostics.json`，包含工具 schema、参数名、文本字节数、结果类型及错误，不主动记录台词、Authorization、OAuth token 或签名 URL 的查询参数。`generation_submitted` 表示已提交生成，`outcome_unknown` 表示无法确定服务端执行结果，不能据此自动重试。

最初的源码诊断使用本地模拟 MCP 和 HTTP 客户端，未调用真实生成、未充值或自动重试；随后按用户要求用加密脚本构建 debug，并覆盖安装到测试机。本版 Android / Windows release 的构建、产物与验证结果见 [1.0.4.1 MCP FishAudio 更新说明](CHANGELOG_1.0.4.1_MCP_FishAudio.md)。模拟音频头用于容器校验，不代表真实播放、扣费或听感验证。仍需用户授权的真实生成诊断，才能确认历史 StateError 的具体触发点。

官方依据：[MCP 官方说明](https://docs.fish.audio/overview/mcp.md)、[官方插件工具用法](https://github.com/fishaudio/fish-audio-plugin/blob/71c656a183618db3d3b6dcd4947ed59d4dc30117/plugins/fish-audio/skills/fish-audio/SKILL.md)。完整 schema 以实际账号的 tools/list 为准。

## 首次接入时的公开端点探测

在未授权状态下对官方端点只做了初始化探测，没有注册客户端、调用 `tools/list` 或生成语音：

- `POST https://api.fish.audio/mcp` 返回 `401`，保护资源元数据为 `https://api.fish.audio/.well-known/oauth-protected-resource/mcp`。
- 授权服务器为 `https://api.fish.audio`，scope 为 `mcp`，支持 PKCE S256。
- 授权端点为 `https://fish.audio/oauth/authorize/`，token 端点为 `https://api.fish.audio/oauth/token`，动态注册端点为 `https://api.fish.audio/oauth/register`。
- Fish Audio API 有 `drama-3` 模型，但 MCP 是否在 tools schema 中暴露它必须以授权后的 `tools/list` 结果为准；当前不能宣称 MCP 支持 Drama 3，也不会隐式改用 REST 计费端点。
- 官方文档说明 MCP 语音生成使用账号套餐积分；端点初次探测时未登录账号，未核验当前账号套餐余额或实际扣费。

## 首次使用

1. 打开“设置 → TTS → Fish Audio MCP（OAuth）”。
2. 点击“登录并探测 tools/list”，在浏览器完成 Fish Audio 登录和授权。
3. 浏览器回调回应用后会自动连接，直到显示“工具已探测”。
4. 查看工具列表和 Drama 3 状态；只有识别到 TTS 工具后才可以将 Provider 保存为 MCP。
5. 选择模型和音色；服务默认表示不指定模型。当前工具不支持所选模型参数时会在生成前报错，可以选择服务默认并保存。已开启的 REST 回退使用原有 API 配置，与 MCP 模型选择分别保存。

如果授权页面无法自动回到应用，请保留页面中的回调地址并重新打开应用后再次连接；当前 PKCE 状态只在本次进程内有效，进程被系统杀死后需要重新发起登录。

## Windows OAuth 回调与打包

Windows 与 Android 使用同一份 MCP 服务、参数校验、诊断和聊天/ASMR 代码。Windows 启动时为当前用户注册 `fishmcp` 协议，命令中的 EXE 路径和回调参数均带引号，支持包含空格的安装目录。请先把完整 Windows 包解压到固定目录，再运行其中的 `AgentAtelierR.exe`，不要仅复制 EXE 或从压缩包临时目录打开。

浏览器完成授权后，Windows 会用 URL 协议启动应用进程。入口现在先调用 `app_links 7.2.2` 官方的 `SendAppLinkToInstance()`，把链接转交给已运行的同一路径应用并结束临时进程；原应用的 `AppLinks().uriLinkStream` 接收回调，使用原进程内保存的 PKCE state/verifier 完成交换。此前只有协议注册而没有转交逻辑，回调会进入不持有 PKCE 状态的新进程并被拒绝。

此修复已按本地 SDK 的公开头文件、插件实现和 Windows 示例进行静态核对。未启动应用或浏览器、未进行真实 Windows OAuth 授权；原进程退出、不同路径版本同时运行或应用以管理员权限运行时的浏览器回调仍需实际验证。PKCE 状态不跨进程持久化，授权期间应保持原应用运行并使用普通用户权限。

Windows 发布包需要包含完整 Release 目录及生成的插件和 `data` 资源，包括 `app_links`、`url_launcher_windows`、`flutter_secure_storage_windows`、音频和 Spine 运行库。是否成功编译和包含这些文件以对应发布产物检查为准；插件已列入生成的 CMake 注册列表，不代表旧的 Release 目录已经更新。

## 尚未验证

- 需要用户账号授权后才能确认 Fish Audio 实际工具名、输入 schema、音频返回结构和 Drama 3 是否可选。
- 尚未发起真实语音生成，因此没有进行积分消耗测试，也没有声线效果结论。
- StateError 修复后的加密 Android debug 已覆盖安装；本版两端 release 的编译与包体校验不代表真实生成、Windows OAuth 或试听验收。

## 回滚

本次改动前的本地存档为标签 `backup/pre-fish-audio-mcp-20261015`，对应 bundle：

`build/archives/pre-fish-audio-mcp-20261015/ryza_chat_mvp.git.bundle`

StateError 修复前另有本地标签 `backup/pre-fish-mcp-stateerror-20261015`。

回滚前请先保存当前工作区，并使用该标签或 bundle 恢复。不要删除用户已有的 `docs/user_manual_2026-10-08/` 和 `evidence/` 未跟踪目录。
