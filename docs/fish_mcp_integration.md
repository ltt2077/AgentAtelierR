# Fish Audio MCP 接入与 StateError 诊断

本次加入了独立的 Fish Audio MCP TTS Provider。原有 Fish Audio REST、百炼、通用 OpenAI TTS、MiMo 和本地 CosyVoice 仍然保留；MCP 不会进入 LLM 请求链，也不会覆盖普通 API Key。

## 已实现

- 使用 `mcp_dart 2.4.3` 连接 `https://api.fish.audio/mcp` 的 Streamable HTTP。
- 新增 `Fish Audio MCP（OAuth）` TTS Provider，聊天和持续 ASMR 共用现有音频缓存、响度均衡、立体声和 Spine 播放流程。
- 使用 Fish Audio OAuth Authorization Code + PKCE（S256）。首次点击设置页的“登录并探测 tools/list”时才进行动态客户端注册和浏览器授权。
- OAuth access token、refresh token、有效期和客户端 ID 使用独立的安全存储命名空间；普通 API 服务导出不会包含这些内容。
- 授权回调使用 `fishmcp://oauth/callback`。Android 已配置 intent-filter，Windows 使用 `app_links` 的同一自定义 scheme；Windows 启动时会在当前用户注册 `fishmcp` URL 协议。
- 授权后先执行 `tools/list`，保存工具名、描述和完整 input schema；未完成工具探测时，生成请求会被阻止。
- 参考工具 schema 的参数名构造请求，取消客户端 schema 拒绝校验；按用户要求保留所选模型的透传，使用声明的模型别名或默认 `model` 字段。用户最新提供的真实 schema 没有模型选择字段，且 `additionalProperties: false`，所以透传模型属于公开契约之外的参数，不能保证服务接受或采用。
- 支持 MCP 返回的内嵌音频，以及 `https://*.fish.audio` 音频 URL；拒绝非 HTTPS 或非 Fish Audio 域名。
- MCP 连接失败不会自动删除现有 Fish REST 配置。设置页保留 MCP 失败回退开关字段，原有 Provider 可随时切回。
- MCP 模型提供下拉选择：`s2.1-pro-free`、`s2.1-pro`、`drama-3`，兼容已保存的自定义值；“服务默认”不指定模型。客户端不根据 schema 阻止模型选择或提交。
- 模型和音色修改先作为本页草稿，点击“保存并使用 MCP”后下次调用才生效；返回或取消不会自动保存。模型下方显示最近请求、云端返回及状态，草稿与最近请求不同时会标明旧记录不能作为本次选择的结果。
- 普通音色与 ASMR 音色分别设置，ASMR 留空沿用普通音色；持续 ASMR 始终优先使用 ASMR 音色。已有单音色配置兼容为普通音色，新字段支持持久化与普通配置备份。科洛蒂娅固定音色 ID 在页面只读显示，MCP 模式下和主角共用当前 MCP 模型与连接，仅为真实台词生成语音。

## 2026-10-15 StateError 修复

旧实现把工具错误、未找到音频、下载失败等多种情况包装为 `StateError`，而回退日志只记录异常类型，导致真实原因丢失。现在保留错误的 `stage`、`code`、`message`、可用的 HTTP status 和 request ID，设置页可以复制脱敏诊断和完整工具 inputSchema。

- 优先选择真正的 `text_to_speech`，排除搜索、余额等说明中提到 TTS 的非生成工具；支持工具分页，重新发现失败时禁用旧工具。
- 语言随角色设置映射，模型与音色可直接配置。按用户要求取消本地必填项及枚举的拒绝校验，保留真实服务返回的错误，不会因 schema 未列模型而自动转入 REST。
- 解析 AudioContent、ResourceLink、EmbeddedResource、Markdown 链接、嵌套 JSON，以及数组或字符串形式的 structuredContent；按实际音频容器保存文件后缀。
- 下载不携带 OAuth 凭据，逐次验证 HTTPS 重定向，限制超时和文件大小。未知外部 CDN 明确报域名错误，不自动信任所有主机。
- 设置页实时反映异步 OAuth / 连接状态，断开后丢弃晚到结果；日志区分选择的 provider 与实际使用的 provider。
- REST 回退默认关闭，保留用户以前明确保存的开关值。开启时，仅在本地准备失败、尚未提交 MCP 生成时允许回退；回退沿用明确选择的 MCP 模型，只有选择“服务默认”时才使用原 API 模型。提交后结果未知、工具报错、下载或音频校验失败均不自动回退或再次生成。

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
- Fish Audio API 有 `drama-3` 模型。客户端按用户要求允许 MCP 提交所选模型；后续取得的真实 MCP schema 没有模型选择字段，不能因此推定 REST 的模型切换能力同样适用于 MCP。
- 官方文档说明 MCP 语音生成使用账号套餐积分；端点初次探测时未登录账号，未核验当前账号套餐余额或实际扣费。

## 首次使用

1. 打开“设置 → TTS → Fish Audio MCP（OAuth）”。
2. 点击“登录并探测 tools/list”，在浏览器完成 Fish Audio 登录和授权。
3. 浏览器回调回应用后会自动连接，直到显示“工具已探测”。
4. 查看工具列表和 Drama 3 状态；只有识别到 TTS 工具后才可以将 Provider 保存为 MCP。
5. 选择模型和音色后，点击“保存并使用 MCP”；返回或取消会丢弃本页草稿。服务默认表示不指定模型。所选模型按用户要求透传，但当前真实 MCP schema 没有此字段，不保证云端采用。已开启的 REST 回退使用原有 API Key 和音色，模型沿用明确选择的 MCP 模型；只有 MCP 选择服务默认时才使用原 API 模型。

如果授权页面无法自动回到应用，请保留页面中的回调地址并重新打开应用后再次连接；当前 PKCE 状态只在本次进程内有效，进程被系统杀死后需要重新发起登录。

## 2026-10-16 模型选择排查与本轮更新

用户提供的日志显示：00:07 的调用因旧版客户端 schema 校验而回退 REST；00:30 和 00:31 的调用均选择 `drama-3`，`actualProvider` 为 Fish Audio MCP。后两次不能归因于 REST 回退。用户同时反馈 Fish Audio 网页生成记录仍显示 S2.1 Pro。

用户随后提供了实际 `text_to_speech` 的完整 inputSchema，已确认公开输入契约如下：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `text` | 是 | 要生成语音的文本。 |
| `voice_id` | 否 | 指定音色 ID。 |
| `language` | 否 | 仅在未指定 `voice_id` 时，用于选择默认音色。 |

`properties` 只有以上三个字段，`required` 只有 `text`，并明确声明 `additionalProperties: false`。其中没有 `model`、`model_id` 或其他模型切换字段。`language` 不能据此解释为切换已选音色的语言或更换生成模型。

因此，当前 MCP 公开契约并不承诺按请求切换模型。客户端继续按用户要求透传模型配置，不能把请求中带有 `model=drama-3` 当作云端采用了 Drama 3 的证据；额外参数也可能被服务拒绝或忽略。现有事实与“通过 MCP 请求但网页仍显示 S2.1 Pro”并不矛盾，尚需服务端明确的实际模型响应或官方说明才能确认具体处理方式。

当前源码修复并增加以下诊断：

- 聊天及持续 ASMR 的授权回退保留明确选择的 MCP 模型，避免使用旧 API 模型；普通 API 模型设置独立保存。
- 设置页区分尚未保存的草稿与最近已提交的请求，展示最近请求模型、云端返回模型及状态。未返回模型标识时明确显示无法确认切换，不把下拉选择或音频生成成功当作模型已生效。
- 脱敏诊断新增 `requested_model`、`reported_model`、`model_selection_status`；仍包含真实工具 inputSchema 和实际参数名。云端返回标识只是响应证据，与请求一致也不等于独立验证了后台执行模型；不同标识可能存在别名，需结合官方说明或生成记录判断。
- 返回模型提取先在结构化结果、元数据、附加字段及 JSON 文本中查找明确的 `actual_model`、`used_model`，再查找普通的 `model`、`model_id`、`modelId`、`model_name`、`modelName`。明确的实际模型字段优先于外层普通模型回显；不会从自然语言、音色名称或请求参数对象猜测模型。
- 并发请求按提交顺序归属最近的诊断，较早响应或失败不会覆盖较新的模型记录与日志。本地准备失败不抹掉上次已提交请求的证据；连接取消后的晚到结果也不能作为当前连接的模型结果。

设置页的调用状态包括暂无记录、请求中、请求失败、服务默认、云端未返回、返回一致及返回不一致。“返回一致”只说明响应元数据与请求相同；“云端未返回”会明确提示无法确认切换，不能把它解释为已经使用所选模型。

如需留存后续证据，请在 MCP 设置页展开 `text_to_speech`，点击“复制工具与完整 inputSchema”；也可点击“复制连接 / 错误诊断（已脱敏）”。本轮已取得用户提供的真实 schema，无需为此重新生成语音。客户端继续按用户要求透传所选模型，不自动追加其他未经证实的字段或 REST 请求头，也不自动重试生成。

本轮验证：完整测试 1375 项通过、61 项跳过，包含 107 项 MCP 协议、运行时、配置及设置测试；完整 `flutter analyze --no-pub` 无问题。真实工具定义已保存为 `test/fixtures/fish_mcp_text_to_speech_2026-10-16.json`，用于确认无模型字段时继续透传、准确提示契约限制且不误报成功。均为本地验证，未调用真实生成或消耗积分。新加密构建、包体检查与附件哈希见[发布说明](CHANGELOG_1.0.4.1_MCP_FishAudio.md)。

## Windows OAuth 回调与打包

Windows 与 Android 使用同一份 MCP 服务、模型透传、诊断和聊天/ASMR 代码。Windows 启动时为当前用户注册 `fishmcp` 协议，命令中的 EXE 路径和回调参数均带引号，支持包含空格的安装目录。请先把完整 Windows 包解压到固定目录，再运行其中的 `AgentAtelierR.exe`，不要仅复制 EXE 或从压缩包临时目录打开。

浏览器完成授权后，Windows 会用 URL 协议启动应用进程。入口现在先调用 `app_links 7.2.2` 官方的 `SendAppLinkToInstance()`，把链接转交给已运行的同一路径应用并结束临时进程；原应用的 `AppLinks().uriLinkStream` 接收回调，使用原进程内保存的 PKCE state/verifier 完成交换。此前只有协议注册而没有转交逻辑，回调会进入不持有 PKCE 状态的新进程并被拒绝。

此修复已按本地 SDK 的公开头文件、插件实现和 Windows 示例进行静态核对。未启动应用或浏览器、未进行真实 Windows OAuth 授权；原进程退出、不同路径版本同时运行或应用以管理员权限运行时的浏览器回调仍需实际验证。PKCE 状态不跨进程持久化，授权期间应保持原应用运行并使用普通用户权限。

Windows 发布包需要包含完整 Release 目录及生成的插件和 `data` 资源，包括 `app_links`、`url_launcher_windows`、`flutter_secure_storage_windows`、音频和 Spine 运行库。是否成功编译和包含这些文件以对应发布产物检查为准；插件已列入生成的 CMake 注册列表，不代表旧的 Release 目录已经更新。

## 尚未验证

- 已取得用户提供的真实 `text_to_speech` inputSchema；其中没有模型切换字段。仍未取得证明云端实际执行模型的元数据、额外 `model` 参数处理规则及各模型权益证据；模型下拉与本地模拟测试不能代替在线验收。
- 本轮修复没有发起真实语音生成，没有新增积分消耗或声线效果结论。用户已有两次调用日志显示走 MCP，尚不能确定为何网页记录仍显示 S2.1 Pro。
- 早先 StateError 修复后的加密 Android debug 已覆盖安装，上一轮也有两端 release；这些旧产物不代表本轮模型诊断修复已交付。新构建状态见发布说明，包体检查也不能代替真实云端模型、Windows OAuth 或试听验收。

## 回滚

本次改动前的本地存档为标签 `backup/pre-fish-audio-mcp-20261015`，对应 bundle：

`build/archives/pre-fish-audio-mcp-20261015/ryza_chat_mvp.git.bundle`

StateError 修复前另有本地标签 `backup/pre-fish-mcp-stateerror-20261015`。

回滚前请先保存当前工作区，并使用该标签或 bundle 恢复。不要删除用户已有的 `docs/user_manual_2026-10-08/` 和 `evidence/` 未跟踪目录。
