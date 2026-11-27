# 翻译阅读

在设置中开启“翻译阅读”，选择本地或在线服务，并配置目标语言。在线提供预设地址和模型选择，本地填写已安装的模型名。目标语言默认跟随当前系统语言，与应用界面语言分开；也可指定中文、英文、西班牙语、日语、法语或德语。

播放顺序按原文段落循环：原文、译文、可选背景介绍、原文复读。换行作为段落边界；极长段落按最多 12,000 字符分段处理。译文和背景不写进原书，不参与书库云同步。原文段落完成整个循环后才提交进度，避免译文或背景的字符偏移污染原书位置。同一播放会话暂停时保留当前阶段；媒体时钟引擎保留当前音频位置，纯系统直接朗读可重读当前短语音块。重新打开应用从已保存的原文段落继续。

设置页“加入背景介绍”和听书页“背景介绍”按钮共用本机持久化状态。播放页点击会翻转状态：在译文阶段开启会补充生成背景；背景正在播放时关闭会停止该阶段并进入原文复读。已经过了背景阶段时开启，对下一段生效。背景是模型生成的辅助解释，并非经检索验证的历史资料，界面明确标记仅供参考。

## 服务配置

- 本地：Ollama 基础地址，例如 `http://127.0.0.1:11434`，以及用户已安装的模型名。应用调用 `/api/chat`，要求 JSON 输出，不自动下载模型或启动服务器。手机的 localhost 是手机自身；连接电脑需填写电脑可访问地址。Android 明文连接仅允许 localhost、127.0.0.1、10.0.2.2 和 `.local` 主机；局域网 IP 请通过 HTTPS 暴露服务或改用 `.local` 主机名。iOS/macOS 声明本地网络用途，初次连接可能需要系统授权。
- 在线：支持 JSON 输出的 OpenAI 兼容 Chat Completions 服务；基础地址通常以 `/v1` 结束，应用追加 `/chat/completions`。必须 HTTPS。API 密钥保存在系统安全存储，按服务基础地址隔离，更换地址不会自动带上旧服务密钥。不会将密钥写入普通偏好或源码，不跟随 HTTP 重定向转发密钥。

只有开启翻译阅读并播放时才调用服务。在线服务接收当前原文段落、书名和章节，可能收取费用。配置页面明确说明，不默认选择或调用任何在线供应商。服务不可用、返回错误或无效 JSON 时停止本次翻译听读并保留原文进度，不伪造译文。接口限时并限制响应大小。

模型须返回 JSON：`translation`、`background`、`sourceLanguage`。原文语言由模型识别，译文和背景按目标语言朗读；使用当前选择的系统语音或 Melo。Melo 仅支持中文和英文，其余语言需选择系统语音并安装对应音色。模型与语言的实际质量取决于用户配置，尚未完成真实在线服务、真实本地模型或四端真机长时间验收。

参考接口：[Ollama Chat API](https://github.com/ollama/ollama/blob/main/docs/api.md)、[Chat Completions JSON 输出](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=chat)、[Apple 本地网络 ATS 配置](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)。

验证：9 项数据／播放状态机单元检查通过，覆盖默认语言、快速开关持久化、四阶段顺序、暂停续播、播放中背景开关、服务地址与密钥隔离、服务失败时进度保护；静态检查通过。未运行模拟器或界面模拟测试，未打包和发布。

## 在线服务预设与文字点击

提供 OpenRouter、OpenAI（ChatGPT 系列）、Google Gemini 与自定义服务。选择预设后自动填写地址和默认模型。OpenRouter 也预设 OpenAI 和 Gemini 模型选项，可用同一 OpenRouter 授权调用。默认模型依据 2026-11-26 官方文档和公开目录，服务商后续可能调整可用性。

OpenRouter 提供 PKCE 登录授权：通过系统浏览器登录、用户批准后，校验回调地址与随机 state，携带一次性 verifier 换取该用户的 API key，保存到系统安全存储。Windows 使用 localhost:43823，Apple／Android 使用既有 bookworm URL scheme。提供手动密钥回退。登录回调有单元检查，但尚未完成真实账号四端登录验收。

OpenAI／Gemini 提供官方密钥页面入口；网页账号登录本身不等于第三方应用 API 授权，用户取得 API key 后首次绑定一次。应用不读取浏览器 cookie 或账号密码。移除本机授权只删除本地密钥，撤销远端密钥需要到服务商页面操作。

原文页点击当前高亮句：播放中暂停，再次点击继续；点击其他区域仍控制工具栏。翻译播放页点击当前展示的播放文字也会暂停／继续。点击联动完成代码检查，未运行界面模拟测试。

参考：[OpenRouter PKCE](https://openrouter.ai/docs/guides/overview/auth/oauth)、[OpenRouter 模型目录](https://openrouter.ai/api/v1/models)、[Gemini API 密钥](https://aistudio.google.com/docs/api-key)、[Gemini OpenAI 兼容接口](https://aistudio.google.com/docs/openai)、[OpenAI 与 ChatGPT 计费区分](https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform)。


## 古今语言转换

翻译也包含同一语言的古今转换。目标为中文时，文言文译为现代汉语；目标为英文时，古英语或中古英语译为现代英语。原文仍按既有流程朗读，不因同语种而跳过译文。背景介绍仍可独立开关。系统 TTS 使用现代语音，不能保证复原古代发音；翻译质量依赖所选模型，尚未完成真实模型验收。

2026-11-27：macOS 本地 Release 1.0.10（12）已生成，Developer ID 签名并验签，未公证；15 项相关单元检查通过、静态分析无问题。其他平台尚未打包本轮修复。古今翻译质量和真实在线服务调用等待手动验收。
