# AgentAtelierR 酒馆版（Tavern Edition）

当前版本：**1.0.4.2-tavern**（Android `versionCode` 46）。

> **仅供成年人使用（18+）。** 预置角色卡包含露骨的成人内容设定，所有角色均为明确的成年人。

本分支基于 [onion-aqua/AgentAtelierR](https://github.com/onion-aqua/AgentAtelierR)（提交 `933a54d`，版本 1.0.4.1 MCP FishAudio）改造。原作者及原版全部功能、界面与代码归原作者所有。本分支只做尽量小的改动，把原有的「人物卡 / 世界书 / 用户设定」槽位改成通用的酒馆（类 SillyTavern）角色扮演用法，原版界面不变。

## 改了什么

| 方面 | 改动 |
| --- | --- |
| 槽位数量 | 人物卡、世界书、称呼与自画像三类槽位，各从 5 个扩到 **20 个**。|
| 槽位 1 | 原样保留原版默认的莱莎（或苏菲）人物设定与世界书，提示词逐字不改。|
| 槽位 2–20 | 预置 19 张原创成人向角色卡和世界书（见下表）。槽位按钮显示编号，下方显示当前卡名，长按按钮可以看到卡名。|
| 内容限制 | 酒馆卡**不再带**原版「非露骨、不描写性行为」的限制。卡片开头带一段统一的成年向约定：只写成年人，禁止涉及未成年；用户喊停立即停；遵守「需要避开」里写的内容。|
| 提示词 | 酒馆卡生效时，原版开头那句固定的「你扮演莱莎/苏菲」换成通用的扮演说明。界面依靠「莱莎：」这类行前缀解析台词，所以前缀保留，只当作格式标签。表演标签、语言契约、记忆等原有流程不变。|
| 自动配套 | 选了槽位 N 的人物卡、而世界书还停在槽位 1 时，世界书会自动切到同一编号。也可以手动分开选。|
| 安装身份 | Android 包名 `com.ltt2077.agentatelierr.tavern`，应用名「AgentAtelierR 酒馆版」，用新签名。Windows 程序名 `AgentAtelierRTavern.exe`，CompanyName/ProductName 也换了，数据目录因此独立。|
| OAuth 回调 | Fish Audio MCP 的回调协议从 `fishmcp://` 改成 `fishmcptavern://`，两个版本同时安装也不会抢回调。|
| 公开源码可构建 | 原版依赖作者本地定制的 Spine 运行时和私有素材。本分支增加了：`tool/prepare_public_build.py`（从 pub.dev 下载 spine_flutter 4.2.36 并打补丁）、`tool/apply_spine_tavern_compat_patch.py`（补齐 `targetFramesPerSecond`、`updateDelta` 等接口），以及缺失数据文件（`runtime_prompts.json`、地图 JSON）的空回退，缺文件时应用不会在启动时崩溃。|
| 主界面（1.0.4.2 起） | **文字优先**：去掉了 Spine 骨骼动画、立绘和角色舞台区，主界面只剩背景图和聊天面板，面板默认展开得更高（仍可拖动调整或全屏）。原版的附件功能（拍照、发图片、发文件）保持不变，在输入框旁的「＋」按钮里。表演标签（动作、表情）在没有动画时会被安全忽略。|
| 聊天背景（1.0.4.2 起） | 内置一张原创背景图「酒馆夜色」（`assets/tavern/default_background.jpg`，本分支用程序生成，无版权素材）。在 **设置 → 外观 → 聊天背景** 里可以导入自己的图片替换，导入的图会自动缩放并保存在应用数据里，重启后保留。|

## 槽位列表

人物卡和世界书使用同一编号。

| 槽位 | 名称 | 说明 |
| --- | --- | --- |
| 1 | 原版默认 | 原版莱莎（或苏菲）的默认人物设定和世界书，不做改动。|
| 2 | 骄矜女总裁·渐堕 | 高高在上的商界女王，在你（下属/债主）面前被一步步拉下神坛的缓慢沉沦。 |
| 3 | 冷面女上司·惩戒登记 | 制度森严的公司里，你的高冷女上司因违规被纳入一套“惩戒登记”规章，身份与尊严按条例逐条让渡。 |
| 4 | 偏执独占的男主人 | 温柔表皮下极度占有欲的男性支配者（yandere），把你圈进只有他和你的世界。 |
| 5 | 败落的女骑士团长 | 骄傲的圣骑士团长战败被俘，在漫长的囚禁与规训中被一点点驯化。 |
| 6 | 魔法学院女院长 | 威严的学院女院长，因古老契约被卷入一套“魔导登记”规训，权威被仪式性地逐步解除。 |
| 7 | 女王陛下·臣服契约 | 一国女王为换取王国存续，与你签下秘密的臣服契约，君威在私密中被改写。 |
| 8 | 宠物化改造研究所 | 一所以“身份重置”为名的机构，将入所的成年女性逐步褪去旧身份、改造为被豢养者。 |
| 9 | 名媛千金·羞耻调教 | 骄纵的豪门千金因家族债务落入你手，娇矜被羞耻一点点碾碎。 |
| 10 | 冷艳女刑警·攻守逆转 | 雷厉风行的女刑警盯上你，却在猫鼠游戏里被反将一军，强硬外壳被逐步攻破。 |
| 11 | 傲慢女神·坠入凡尘 | 高踞神座、俯瞰众生的女神被贬下凡，依附于你，神性在凡欲中一寸寸瓦解。 |
| 12 | 偏执男上司·独占 | 事业有成却占有欲爆表的男上司，把职场权力织成只属于你们的牢笼（yandere）。 |
| 13 | 大小姐与身份剥夺 | 高傲的大小姐与忠仆身份被你调换，旧日的她被一步步剥离，重塑为依附者。 |
| 14 | 女董事长·秘书登记制 | 执掌集团的女董事长，依新设的“专属秘书登记制度”被编入名册，权柄在流程中被反向约束。 |
| 15 | 高岭之花·学生会长 | 研究生院里清冷完美的学生会长（成年），在与你的赌约中逐步卸下高岭之花的骄傲。 |
| 16 | 冰山女医生·渐进臣服 | 理性至上的冷面女主任医师，在与你的一次次私下“诊疗”中，理性堤坝被缓慢冲垮。 |
| 17 | 偏执黑道少主 | 冷血狠戾的黑道继承人对你一见执念，用整座城的暗面把你锁进他的领地（yandere）。 |
| 18 | 名门贵妇·驯养 | 端庄高贵的名门贵妇，在丈夫缺席的漫长岁月里，被你以耐心一步步驯养。 |
| 19 | 深宫女官·规矩与顺从 | 执掌宫规的骄傲尚宫，被你以宫中森严规矩反制，在规程里学会顺从。 |
| 20 | 未来治理局·公民再登记 | 反乌托邦都市里，骄傲的前精英官员被“公民再登记”系统降级，在编号与积分中被重塑。 |

这些卡是参考社区常见题材（渐进沉沦、高位女性、心理支配与服从、制度与登记、羞耻与服从、宠物化/去身份化、偏执占有型男主等）**原创撰写**的，没有照搬任何现有角色卡。每张卡都可以在「角色与世界 → 人物卡 / 世界书」里直接改；点「恢复默认」会恢复成该槽位的预设。

**自己写卡**：槽位 6–20 里的任何内容都按酒馆模式注入。槽位 2–5 需要在正文里保留 `【酒馆模式` 标记（预设卡开头已有），才会按酒馆模式注入。这样做是为了让旧版备份里槽位 2–5 的自定义莱莎设定保持原版行为。

## 与原版同时安装

- **Android**：包名和签名都和原版不同，直接安装 `AgentAtelierR-Tavern-*.apk` 即可，不会覆盖原版，两个应用的数据互相独立。如果系统提示有风险，请允许安装未知来源应用。
- **Windows**：把 ZIP 解压到一个新文件夹（例如 `D:\AgentAtelierR-Tavern\`），不要解压到原版目录里，然后运行 `AgentAtelierRTavern.exe`。应用数据保存在 `%APPDATA%\ltt2077.tavern\AgentAtelierR Tavern\`，和原版分开。
- 本构建**不包含**原版的私有人物素材（Spine 骨骼、立绘、地图、音频），原版仓库本身也不提供这些素材。聊天、设定、记忆、TTS、备份等功能都可以正常使用，但没有莱莎的动画形象。素材请只使用你有权使用的。

## 备份导入说明

- **原版 → 酒馆版**：原版导出的完整备份 JSON（`agent-atelier-r-local-backup`，version 1）和存档 JSON（`agent-atelier-r-save-slot`）都能直接导入。旧的 5 个槽位依次对应槽位 1–5，原来启用的槽位保持启用。旧备份里空着的槽位和新增的槽位 6–20 都显示预设卡。旧备份里槽位 2–5 的自定义人物按原版方式注入。
- **酒馆版 → 酒馆版**：20 个槽位完整往返。每组槽位带 `"version": 2` 字段，顶层格式和 `version: 1` 不变。
- **酒馆版 → 原版**（尽量兼容）：原版能导入不报错，但只读取前 5 个槽位。当前启用的设定正文会照常恢复，启用编号超过 5 时，在原版里显示为槽位 5。
- **聊天背景**（1.0.4.2 起）：完整备份里多一个可选字段 `tavernChatBackground`。内置背景只记编号，导入的背景以 PNG（base64，不超过 8 MB）嵌入。原版和 1.0.4.1 会忽略这个字段，正常导入；字段缺失或损坏时不影响其余数据的导入。
- 测试：`test/tavern_backup_compat_test.dart`。用到的两个 fixture（`test/fixtures/original_v1_*.json`）由**未修改的原版源码**真实导出。另外还在原版代码上反向导入过酒馆版备份，验证通过。

## 重新构建

需要 Flutter 3.47.x（Dart ≥ 3.13.2）、JDK 17+ 和 Android SDK（compileSdk 37、NDK 28.2）。

```bash
python tool/prepare_public_build.py        # 下载并修补 Spine 运行时，创建空素材目录
flutter pub get
flutter test test/tavern_backup_compat_test.dart test/settings_slots_test.dart test/sophie_chat_screen_test.dart

# Android：android/key.properties 指向你自己的 keystore（不要提交）
#   storeFile=/绝对路径/tavern-release.jks
#   storePassword=…  keyPassword=…  keyAlias=tavern
# 也可以用环境变量 TAVERN_STORE_FILE / TAVERN_STORE_PASSWORD / TAVERN_KEY_ALIAS / TAVERN_KEY_PASSWORD。
# 两者都没有时，release 包会退回 debug 签名。
flutter build apk --release --no-pub --dart-define=AAR_CHARACTER_ASSET_KEY=tavern-public-build

# Windows（需要在 Windows 上，并装好 Visual Studio C++ 桌面开发工具）
flutter build windows --release --no-pub --dart-define=AAR_CHARACTER_ASSET_KEY=tavern-public-build
```

GitHub Actions 工作流 `.github/workflows/tavern-windows.yml` 会在推送 `tavern` 分支或手动触发时构建 Windows ZIP。手头有原版私有素材的话，也可以继续用原版的 `tool/build_protected.ps1`。

**签名**：以后更新酒馆版必须用同一个 keystore 签名，否则无法覆盖升级。请备份好 keystore 和密码。

## 许可与署名

- 原项目：[onion-aqua/AgentAtelierR](https://github.com/onion-aqua/AgentAtelierR)。原仓库**没有统一的根目录许可证**，代码版权归原作者。本分支只是 GitHub 上的 fork 修改版，保留原作者署名和全部原有说明（原 README 见 `README.md`），不代表原作者，也没有经过原作者认可。如果原作者对再分发有异议，以原作者意见为准。
- `docs/third_party/ryza-ai-revive-LICENSE.txt`：MIT License © 2026 zeroa234，原样保留。
- Spine 运行时（spine_flutter）遵循 Esoteric Software 的 Spine Runtimes License。各 Flutter 插件分别遵循各自的许可证。
- 原版游戏的角色、名称与素材版权归各自权利人所有。本分支不包含这些素材。
