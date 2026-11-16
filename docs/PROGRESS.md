# BookWorm／书虫：实际进度

日期：2026-11-14（America/Detroit）

## 当前有效范围

以需求／系统设计 0.3 为准：本地导入、阅读、系统 TTS、OneDrive／iCloud／Google Drive 本人四端书籍与进度同步。**不加密保存，不做公共书库、交易、借阅、购买或分成。** 用户收敛范围后已授权本阶段实施，不再受 0.2 的“先确认商用全案”门槛约束。

## 已写入代码

- BookWorm／书虫可见名称；书架、听书和私人云三个入口。
- UTF-8 TXT、无 DRM EPUB 文字／章节、PDF 原页与文本提取；单本 ≤50 MB、PDF ≤2,000 页。
- 原件和解析内容普通文件保存、串行写入与临时替换、重复检测、损坏文件保留及旧数据迁移；旧笔记未删除。
- 目录、全文文字检索、前后节、字号与夜间；读听共享小节／字符位置，滚动按文字布局映射位置。
- 分段系统 TTS、暂停续播、语速／音色、定时、本节停止与进度保存；语音异常与保存失败可显示。
- OneDrive／Google Drive 用户授权与 API 连接器；iCloud CloudKit private Web Services 连接器。
- 私人云分块＋哈希校验＋最后提交清单；每设备独立进度，冲突由用户选位置；已处理的远端位置不会每次重复弹窗。
- 四端调试构建 CI 文件已上传 GitHub，运行结果以 Actions 页面为准。

## 验证记录

- 最新 `flutter analyze`：无问题。
- 最新 `flutter test`：13 项通过（解析、迁移、持久化、暂停续接、模拟云传递／损坏拒绝、OneDrive／Google 请求解析及界面）。
- macOS：最终代码 Debug 构建成功；本轮通过原生界面观察启动成功。
- iOS：最终代码模拟器 Debug 构建成功；尚未做真机文件／声音／后台行为测试。
- Android：最终代码 Debug APK 构建成功；尚未完成安卓真机听书与后台行为验收。
- Windows：当前主机无法构建，Windows CI 配置已上传；未以云构建结果代替本机验证。

## 尚未完成的明确边界

1. 三家云均缺真实开发者应用配置，默认安装包显示未配置；没有完成真实授权与四端互通验收。配置与已知风险见 cloud-setup.md；模拟云测试不是接通云账号的证据。
2. iCloud 的四端浏览器授权／安全回调与 token 轮换仍是重点技术验证项，不能以 API 代码存在标记为已支持。
3. EPUB 仅文字和章节，不含图文／复杂 CSS 完整渲染。扫描 PDF 无 OCR，第三方 DRM 不破解。
4. Android 前台媒体服务、锁屏／耳机与各端后台中断恢复尚未完整实现或真机验证；不能把基础 TTS 当后台播放全功能。
5. 第一阶段没有评论／笔记新 UI；旧原型笔记保留原数据，没有清空。全云删除、跨云迁移和多云镜像未做。
6. Debug 包不是商店签名发布包；云账号注册、签名与发行授权不能伪造。

## 下一步

先取得真实云应用配置完成三家云 × 四端验证；补充原生后台播放及四端真机验证。原商业远景后续另行确定，不自动恢复公共书库或加密开发。

用户额度规则：每阶段及长任务之间查询，任一适用窗口剩余 ≤5% 保存进度并停止，不自动使用重置券；等待用户指示恢复。

## 历史说明

早先误按网站路线创建的 owner-private Sites 项目从未发布。`.openai/hosting.json` 是遗留配置，当前 App 不依赖 Sites，不应自动部署该项目。

## 本轮可试用产物

- dist/BookWorm-macOS-debug.zip：本机调试版，已验证启动。
- dist/BookWorm-Android-debug.apk：调试签名 APK，已构建，未安装真机验收。
- build/ios/iphonesimulator/Runner.app：模拟器构建，不能直接作为真机安装包。
- Windows 本机未构建；CI 配置已上传。
- 三家云真实登录仍被缺少开发者应用配置阻塞；没有自动注册云应用或建立账号权限。

## GitHub 上传与签名 App

- 私有仓库 MikeChongZhou/BookWorm 已创建并上传，初次源码远程提交 6980c20b88734ea6e5d3a25bb0b533d12baefcdb，树 e539352fb8aa03f9bf2a564ad0ddfa0ccaf1375f 与本地一致。
- macOS Release 编译成功，嵌套框架及主 App 已用 Developer ID 签名并通过严格验证；未提交 Apple 公证。
- iOS Release archive 和 development IPA 导出成功，版本 1.0.0 (1)，描述文件到期 2027-08-01，登记设备 2 台（不在仓库保存设备标识）。
- 未安装用户手机、未上传 App Store／TestFlight；默认占位图标仍待替换。
- 云登录配置仍缺失，不因签名构建成功而标记云同步实测通过。

## 1.0.1 About 更新

- 按用户要求参考 STG 新增 About，并确认署名／版权为 Fairy Phoenix Foundation。
- 版本由安装包动态读取；新增使用、隐私、普通文件保存、功能边界和第三方许可证／反馈入口。
- macOS 原生 About 菜单连接 Flutter 共用 About 页面。
- 查明旧包三家云连接失败的直接原因是构建中没有真实云应用配置；未注册登录能力不等于用户账号错误。
- 未配置云入口改为“本版本尚未启用登录／查看说明”，本轮没有声称修复实际云授权。
- 静态检查通过；16 项测试通过，新增 About、许可证入口／链接复制与云说明路径覆盖。
- 1.0.1 macOS Release 编译成功，实际菜单 About 路径已验证；iOS 开发签名 IPA 导出成功。版本化签名产物保存在 dist/，macOS 未公证，iOS 仍限已登记设备。

## 2026-11-14 / 1.0.2

- 已撤销同步文件夹选择方案；私人云嵌入设置，主导航三项为书架／听书／设置，macOS Settings… 与 ⌘, 可打开设置。
- 语言默认跟随系统，可手动选择简体中文、English、Español，自动保存、实时切换。22 项测试通过，静态分析无问题；已在签名 macOS App 中实际验证中文切换与恢复跟随系统。
- 已参考 STG 的账号和系统 iCloud 接入，隔离客户端和存储容器。Google 四端身份配置已注册（Apple 同包标识共享一个 iOS 类型客户端，另有 Android 本地签名、Android 辅助 Web、Windows 桌面客户端），仅在本机配置文件保存参数，测试用户可登录。
- Apple 原生容器已创建、App ID 已绑定，专属 Developer ID 描述文件嵌入 macOS 包；iOS development archive/IPA 已签名生成。macOS 已真实登录 iCloud 和 Google Drive，两者均完成空库同步；跨设备传递仍未验收。
- 用户指定 OneDrive 注册必须使用 mike.castlepines@gmail.com，该账号无 Entra 目录；另一个 Microsoft 账号虽有 Default Directory，用户未同意用它注册书虫。等待指定账号完成 Azure／Entra 开通，不借用 STG client ID。
- 用户确认新包标识 com.fairyphoenix.bookworm；旧包标识被 Apple 拒绝注册，新旧应用并存，旧本地书库需另行迁移／重导入。
- 后续真实 Google 验证：成功授权并完成原创示例书导入后的同步，自动同步随后继续成功。示例保留，未操作旧版私人书籍；另一设备下载与位置续接仍需验收。

## 2026-11-15 / 1.0.3

指定账号已开通 Azure 免费账号及默认 Entra 目录；BookWorm OneDrive 原生应用注册、个人账号类型、双回调和两项最小委托权限均已完成。没有复用 STG 身份或数据，没有创建虚拟机／存储账户等 Azure 资源。

macOS 真实 OneDrive 登录与示例书同步成功，重启后再次同步成功；原有 Google／iCloud 配置保留。macOS 与 iOS 1.0.3 (4) 签名安装包已生成，22 项回归测试通过。跨设备下载及阅读续接、iPhone／Android／Windows 实机云授权仍未验收。截图见 dist/BookWorm-1.0.3-onedrive-connected.png。

## 2026-11-15 / 1.0.4 · Melo 与同步状态

- 设置新增系统自带 TTS / MeloTTS 二选一，本机持久化；默认仍为系统。Melo 选择时下载官方 sherpa ONNX 中文／英文资源（167,006,755 bytes），固定 SHA-256 校验、文件流解压、临时目录安装后提交；失败保留系统选项并可重试。
- 四端使用 sherpa_onnx 2.0.1 + audioplayers 6.8.1，本地 CPU 推理在长驻 isolate 中运行。80 字以内片段、下一片段预生成、临时 WAV 播放与退出清理；音频不上传私人云。Melo 无逐字时间戳，暂停按当前片段起点续播，可能重读；系统语音继续使用系统回调位置。
- 同步移除不定进度条与完成弹出提示，在状态条展示上传／下载的完整书籍文件数、阅读进度处理及最终状态；底层 part/manifest/position 不计为用户文件数。损坏或失败文件不递增成功计数。
- MIT 模型版权与许可原文随 App 打包，第三方许可证页面可查看。模型包自身 LICENSE 同样保留。
- Windows 已接入共用实现与原生依赖，现有 GitHub Actions Windows 构建保留；本机无 Windows 编译环境，不能声称 Windows 实机验收。手机音频中断、后台／锁屏与实际性能仍需设备验收。

1.0.4 验证结果：最终静态分析无问题，22 项常规测试通过；大模型原生测试单独运行通过。macOS Release 编译、Developer ID 签名与 strict 验签通过；真实 App 完成模型联网下载／校验／安装，示例书显示正常播放及暂停，无语音错误；实际云同步完成为纯文字状态。iOS 模拟器与 development IPA、Android debug APK 编译通过。三个版本化产物和 SHA-256 清单位于 dist/BookWorm-1.0.4-*。macOS 未公证，iOS 仅登记设备，Android 为调试签名；Windows 本轮未编译，未上传本轮源码到 GitHub。

## 2026-11-15 / 1.0.5 (6) — 读听与下载改造

需求与验收记录见 reading-experience-v0.3.md。新增完整章节／封面、轻量进度保存、非阻塞开书、独立后台音频会话与迷你播放器、章节时间轴／20 秒命令、分页原文／句级高亮／本地笔记／翻页及颜色字体控制。新增两源公版下载与每日缓存扫描，云自动同步改为每日一次，并在读听时安全让出。GitHub 每次上传升级版本号的规则已写入 AGENTS.md。

33 项回归通过，静态分析无问题；《红楼梦》真实本地性能和两个真实书源下载均已验证。iOS 模拟器原生音频前台连续约 90 秒通过。用户指定 Mike Backup iPhone 验收，已安装保留原书库的正常应用版本，未把测试入口装到手机；用户现已确认系统 TTS“持续播放，锁屏控制正常”。未据此声称四端或 Melo 锁屏已完成。每日任务无常驻服务器，完全退出后在下次运行补做。

后续源码 1.0.5（7）补充 EPUB 结构章节识别、旧版章节／进度迁移，以及自动同步仅提示、不弹出进度冲突窗口（由用户手动查看）。最终 iOS 开发 IPA、Android 调试 APK、Developer ID 签名 macOS ZIP 均已构建，使用 build7 文件名保留构建 6；未覆盖手机上的已验收构建 6。待上传 GitHub 并核验 Windows CI；TestFlight 尚未上传。

## 2026-11-16 / 1.0.6 (8) — 语速选项

听书语速改为 0.7、0.8、0.9、1.0、1.1、1.2 倍，按钮与选项统一显示一位小数。静态分析通过；包含此修改的 iOS Release 本地编译及 Mike Backup iPhone 覆盖安装成功，书库保留。已核实共享 Runner Scheme 的 Run 为 Release、Debug executable 关闭；独立自动启动因手机锁屏被系统拒绝，未声称手机界面验收通过。

此前 1.0.5（7）已于 2026-11-15 上传 GitHub 和 TestFlight，Apple 返回 Upload succeeded。本次按发布规则升级为 1.0.6（8），GitHub 与 TestFlight 提交结果以 dist 中发布回执为准。
