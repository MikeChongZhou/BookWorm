# BookWorm 签名构建记录

日期：2026-11-14（America/Detroit）

源码：私有仓库 [MikeChongZhou/BookWorm](https://github.com/MikeChongZhou/BookWorm)，初次功能提交 `6980c20b88734ea6e5d3a25bb0b533d12baefcdb`。

- macOS：Release App，嵌套框架和主 App 使用现有 Developer ID 签名，`codesign --verify --deep --strict` 通过；未做 Apple 公证。
- iOS：Release archive＋development IPA，版本 1.0.0 (1)，最低 iOS 15，使用现有开发签名；描述文件登记 2 台设备，有效至 2027-08-01。
- iOS 开发包仅限已登记设备；不等于任何手机都可安装，未上传 App Store 或 TestFlight。
- 本地文件：`dist/BookWorm-macOS-release.zip`、`dist/BookWorm-iOS-development.ipa`，macOS App 位于 `dist/macos/BookWorm.app`。
- 构建产物与签名／描述文件不进入源码 Git 历史，未导出私人签名密钥。
- 静态检查与 13 项测试此前通过；该次构建未改变功能代码。三家私人云尚未配置真实应用，不宣称已完成云同步实测。
- 默认 Flutter 占位图标仍存在；当前为试用版本，不是商店审核已通过的商业发布。

## 1.0.1 (2) About 更新

- 四端共用 About 页；macOS 菜单 About 接入并通过实际界面验证，署名／版权为 Fairy Phoenix Foundation。
- 静态检查通过，16 项测试通过。macOS Release 与 iOS development IPA 构建成功。
- 产物：`dist/BookWorm-1.0.1-macOS.zip`、`dist/BookWorm-1.0.1-iOS-development.ipa`。
- macOS 使用现有 Developer ID 验证签名，未做 Apple 公证；iOS 仅限描述文件登记的开发设备。
- 云应用身份参数仍缺失；当前版本明确展示未启用登录，不能把提示修正当作云授权已修复。

## 1.0.2 (3) — 设置、语言和独立私人云

正式包标识 `com.fairyphoenix.bookworm`，用户确认独立安装；旧版仍保留。新增设置及语言选择（默认系统），私人云子页，macOS Settings… 菜单／快捷键。已在真实 macOS App 中验证语言切换、iCloud 容器连接、Google Drive 本人账号授权及空书库同步。

安装包：`dist/BookWorm-1.0.2-macOS.zip`、`dist/BookWorm-1.0.2-iOS-development.ipa`。macOS 使用 Developer ID Application 签名并嵌入 BookWorm 专属 iCloud 描述文件，签名严格验证通过；尚未公证。iOS development IPA 仅可装到描述文件登记设备，未上传 App Store／TestFlight，未在实体 iPhone 验收云同步。两端编译均通过，22 项测试通过。

macOS 带 iCloud 权限后，先 `flutter build macos --release --config-only --dart-define-from-file=cloud-config.apple.json`，再 `xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release -derivedDataPath build/macos CODE_SIGNING_ALLOWED=NO build`；对产物嵌入专属描述文件，逐个签名 frameworks/dylibs、最后签主 App，并验证。直接 adhoc 签名不能代替 iCloud entitlement 的 Developer ID 授权。CI 仅编译无签名调试产物。

OneDrive 未注入配置：指定开发者账号缺少 Entra 目录，等待用户开通。Google 安装包目前使用独立项目的测试状态，其他读者不自动获得测试用户资格。

补充真实 Google 验证：用户确认应用专用目录授权后，macOS SDK 成功完成登录；导入仓库原创 `samples/本地读听示例.txt` 后同步完成，后续自动同步仍成功。该示例保留在新版书库中，不涉及旧版私人书籍。尚未以另一设备验证下载／进度续接。证明截图：`dist/BookWorm-1.0.2-settings.png`、`dist/BookWorm-1.0.2-cloud-connected.png`、`dist/BookWorm-1.0.2-google-sync.png`。

## 1.0.3 (4) — OneDrive 接入

本机 cloud-config.apple/android/windows.json 已注入独立 OneDrive 原生客户端 ID；仅书虫 app folder 与 offline_access。真实 macOS 验证：登录成功、示例书同步成功、正常退出并重开后恢复来源、再次同步 0 上传／0 下载且更新成功时间。

产物：dist/BookWorm-1.0.3-macOS.zip（Developer ID 严格签名，嵌入专属 iCloud 描述文件，未公证）；dist/BookWorm-1.0.3-iOS-development.ipa（仅描述文件登记设备，未上架）。两个平台编译通过，22 项测试通过。iPhone、Android、Windows 真实登录与双设备传书／进度续接尚未验收；不把桌面验证当成四端完成。

### Melo 实际原生测试

常规 `flutter test` 不下载大模型；`test/melo_native_test.dart` 默认跳过。使用已下载的官方 tar.bz2，通过 `BOOKWORM_MELO_ARCHIVE` 指定绝对路径、`BOOKWORM_SHERPA_LIB` 指定 sherpa_onnx_macos 包内 `macos` 根目录，再执行 `flutter test test/melo_native_test.dart`。覆盖文件流安装、长驻 isolate 内真实合成、WAV 头／长度及释放。初次错误传入 dylib 文件路径已纠正为库根目录，随后真实测试通过。

Melo 下载压缩包约 167 MB，安装约 191 MB；解压时临时文件会额外占用磁盘。模型采用固定 SHA-256；下载失败重新下载，不使用未完成安装。模型不加入 Git，也不随私人书库同步。
