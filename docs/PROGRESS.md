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
