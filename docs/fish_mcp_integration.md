# Fish Audio MCP 接入说明

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

## 真实探测结果

在未授权状态下对官方端点只做了初始化探测，没有注册客户端、调用 `tools/list` 或生成语音：

- `POST https://api.fish.audio/mcp` 返回 `401`，保护资源元数据为 `https://api.fish.audio/.well-known/oauth-protected-resource/mcp`。
- 授权服务器为 `https://api.fish.audio`，scope 为 `mcp`，支持 PKCE S256。
- 授权端点为 `https://fish.audio/oauth/authorize/`，token 端点为 `https://api.fish.audio/oauth/token`，动态注册端点为 `https://api.fish.audio/oauth/register`。
- Fish Audio API 有 `drama-3` 模型，但 MCP 是否在 tools schema 中暴露它必须以授权后的 `tools/list` 结果为准；当前不能宣称 MCP 支持 Drama 3，也不会隐式改用 REST 计费端点。
- 官方文档说明 MCP 语音生成使用账号套餐积分；本项目尚未登录账号，未核验当前账号套餐余额或实际扣费。

## 首次使用

1. 打开“设置 → TTS → Fish Audio MCP（OAuth）”。
2. 点击“登录并探测 tools/list”，在浏览器完成 Fish Audio 登录和授权。
3. 浏览器回调回应用后，再次点击连接按钮，直到显示“工具已探测”。
4. 查看工具列表和 Drama 3 状态；只有识别到 TTS 工具后才可以将 Provider 保存为 MCP。
5. 音色和模型字段只能填写 `tools/list` schema 中真实存在的参数。留空表示使用服务默认值。

如果授权页面无法自动回到应用，请保留页面中的回调地址并重新打开应用后再次连接；当前 PKCE 状态只在本次进程内有效，进程被系统杀死后需要重新发起登录。

## 尚未验证

- 需要用户账号授权后才能确认 Fish Audio 实际工具名、输入 schema、音频返回结构和 Drama 3 是否可选。
- 尚未发起真实语音生成，因此没有进行积分消耗测试，也没有声线效果结论。
- 当前没有执行 Android/Windows 安装或真机联调；本轮只完成源码、依赖、静态检查和单元测试。

## 回滚

本次改动前的本地存档为标签 `backup/pre-fish-audio-mcp-20261015`，对应 bundle：

`build/archives/pre-fish-audio-mcp-20261015/ryza_chat_mvp.git.bundle`

回滚前请先保存当前工作区，并使用该标签或 bundle 恢复。不要删除用户已有的 `docs/user_manual_2026-10-08/` 和 `evidence/` 未跟踪目录。
