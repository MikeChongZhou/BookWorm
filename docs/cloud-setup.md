# BookWorm 私人云接入配置

当前三种连接器已写入代码，但仓库没有真实开发者应用配置；默认安装包的云登录显示未配置。**未做真实账户登录或四端同步验收，不能把模拟云测试当成已接通云盘。**

书籍按用户要求普通文件保存；仅 OAuth／CloudKit 用户令牌使用系统安全存储，不做书籍加密。内容从 App 直达用户私人云，无书虫中转服务器。

## OneDrive

1. 在 Microsoft Entra 注册面向个人账号的原生／公开客户端应用，登记包名、签名及各端回调。
2. 启用 delegated `Files.ReadWrite.AppFolder` 与 `offline_access`，不配置读取所有用户文件的后台应用权限。
3. 当前回调：Windows `http://localhost:43821/`；其他端 `bookworm://oauth`。必须在注册应用中匹配，并验证相应平台允许的 redirect 类型；不兼容时调整具体端配置，不绕过验证。
4. 构建注入 `ONEDRIVE_CLIENT_ID`。iOS／macOS 和 Android 已登记 `bookworm` 回调 scheme。
5. 首次连接后，在四端使用同一 Microsoft 账号；实际验证 app root、分页、上传／下载、token 刷新、撤权、组织账号差异。

参考：[微软应用专用区域](https://learn.microsoft.com/en-us/graph/onedrive-sharepoint-appfolder)。

## Google Drive

1. 建立同一个 Google Cloud 项目并启用 Drive API，配置 OAuth 同意页和测试用户／发布状态。
2. 为 Android、iOS、macOS、Windows 注册匹配平台的 OAuth 客户端，使用相同项目才能看到同一 appDataFolder。不要把浏览器 Web client ID 当成所有原生客户端 ID。
3. 权限 `https://www.googleapis.com/auth/drive.appdata`。该目录是用户个人空间中应用专用的隐藏区域，不是公共书库。
4. 各端构建传入其 `GOOGLE_CLIENT_ID`。Android 还需配置匹配包名与签名的 Android client，以及 `GOOGLE_SERVER_CLIENT_ID`（Web client ID），或正确的 google-services 注册；凭据配置见插件官方说明。
5. Apple 端在 Info.plist 配置 Google 客户端 reversed URL scheme（不同于已存在的 `bookworm`），并核对对应 SDK 的 Keychain 配置。不能仅传 client ID 就宣称 Apple 登录配置完成。
6. Windows 为桌面 OAuth，回调 `http://localhost:43822/`；如该客户端要求 token exchange 的 installed-app client secret，构建注入 `GOOGLE_DESKTOP_CLIENT_SECRET`。它不应作为服务端机密或访问他人云盘的凭据。
7. 已实现分页、媒体下载、resumable session 上传；断点续传的完整恢复与真实大文件、同名重复、网络超时需进一步验证。

参考：[Google 应用数据](https://developers.google.com/workspace/drive/api/guides/appdata)、[Google 原生应用授权](https://developers.google.com/identity/protocols/oauth2/native-app)。

## iCloud

1. 需要 Apple 开发者账户的真实 CloudKit container，开启用户 Web Services API token，配置允许来源、登录回调和环境。
2. 使用 **private database**。创建 `BookWormObject` 记录类型，`key` 和 `data` 为 STRING；记录名使用 key 的哈希；配置 record type 查询所需的索引并部署 schema 到选定环境。
3. 每块 192 KiB，`data` 是 base64 普通数据，并非加密。清单和进度同样是这个格式。
4. 注入 `ICLOUD_CONTAINER`、`ICLOUD_API_TOKEN`、`ICLOUD_ENVIRONMENT`（默认 production）、`ICLOUD_REDIRECT_URI`。Windows 浏览器回调需要可支持的 localhost 地址，例如 `http://localhost:43823/`；实际 Apple 允许配置与插件响应需先验证。其他端当前默认 `bookworm://cloudkit`，同样必须先确认 CloudKit 接受并能够交接 token；否则这条授权路径是阻塞项，不能标记可用。
5. 连接器只调用 `/private/`，不会使用平台 server-to-server 公共数据库密钥。Apple 密码只在 Apple 官方页面输入，令牌只存本机。
6. CloudKit Web Services 的四端浏览器授权和 token 轮换尚未实测；Apple 登录、安全回调及私人数据访问是否可稳定闭环必须专项验证。失败时保留 iCloud 需求并报告阻塞，不冒充已支持。
7. CloudKit 私人库与 iCloud Drive 可见文件夹不是同一存储；此代码不声称能访问任意 iCloud Drive 目录。

参考：[CloudKit 用户授权与 token](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html)。

## 构建参数

用 `--dart-define-from-file` 注入端别配置，配置文件不要提交 Git。参数名如上；仓库不包含真实值，也不打印登录 token 或授权 URL。

示例：`flutter run -d macos --dart-define-from-file=/你的本地路径/cloud-config.json`。

没有配置时本地导入、阅读和 TTS 仍可用。四端云登录验收前，不能宣称“任意设备直接登录即同步”。

## 1.0.2 接入更新（2026-11-14）

- 取消由用户选择同步文件夹的方案；没有目录选择器／书虫服务器。
- 已参考 STG 的账号直连结构；不会复用 STG 的容器、令牌或 OAuth client ID。
- Apple 原生 iCloud 使用系统 Apple 账号、专属 `iCloud.com.fairyphoenix.bookworm` 容器和 `CloudDocuments` 权限。`NativeICloudProvider` 经 MethodChannel 调用原生文件协调与按需下载；断开仅停同步，不注销系统账号、不删除云端内容。系统会异步上传，其他设备可见有延迟。旧 CloudKit Web Services 连接器保留供研究，但它与 iCloud Drive 的数据并不互通，不作为四端 iCloud 已接通的证明。Android／Windows 首选同一个 OneDrive 或 Google Drive 账号；不宣称 Apple 原生 API 可用于这些系统。
- 正式包标识改为 `com.fairyphoenix.bookworm`：Apple 拒绝注册被占用的旧标识，用户确认更名。新旧 App 并存；旧版书籍需重新导入或另行迁移，尤其 iOS 不能读取另一 App 沙箱。
- 已在独立 Google Cloud 项目创建 Apple（iOS 类型，同包标识供 iOS/macOS）、Windows 桌面、Android 本地测试签名及 Android 登录辅助 Web client；启用 Drive API、`drive.appdata`，目前为 Testing，仅已登记测试用户可登录。公开发布前仍需完成品牌／隐私与上线检查。
- 端别配置在本机 `cloud-config.apple.json`、`cloud-config.android.json`、`cloud-config.windows.json`。这些文件被 Git 忽略；Android 辅助 Web client secret 仅备份在单独的本机管理配置中，不打包进客户端。CI 默认构建不携带本机配置，不能把 CI 包当作云服务已配置的安装包。
- Android 注册当前只匹配本机 debug 签名；正式商店签名／其他开发机必须单独登记 SHA-1。Windows 构建需要本机桌面配置，尚未在 Windows 主机实测。
- Microsoft 指定账号 `mike.castlepines@gmail.com` 没有 Entra 目录，禁止目录外新注册；另一个账号虽有目录，用户选择不使用。等待用户用指定账号开通 Azure／Entra，之后再新建独立 BookWorm 应用。不得借用 STG client ID 假装解决。
- macOS 已成功连接原生 iCloud，完成空书库同步；双端书籍和进度传递尚未验收。Google 真实账号授权验证见构建记录的后续结果。
