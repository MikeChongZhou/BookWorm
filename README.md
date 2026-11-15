# BookWorm／书虫

第一阶段：四端本地导入、阅读、系统 TTS 听书，以及本人私人云书籍／进度同步。书籍按普通文件保存，不加密；不做公共书库、交易、借阅或分成。

## 已实现的本地流程

- TXT（UTF-8）、EPUB 文字／章节、PDF 原版阅读与文本提取；单文件 ≤50 MB。
- 书架、搜索、目录、书内检索、字号、夜间模式和本地读听定位。
- 分段系统 TTS、暂停续听、语速与系统声音、定时关闭及本节结束停止。
- 普通文件持久化、原件保留、重复检测、旧原型数据迁移；异常文件保留并报错。
- OneDrive／Google Drive／iCloud 连接器、分块校验同步和跨设备进度选择，已接入界面。

**1.0.3 云配置**：本机签名 Apple 安装包已注入独立 OneDrive、Google 登录配置与原生 iCloud 容器。三家云在 macOS 均已验证真实连接；OneDrive、Google Drive 已完成示例书同步，OneDrive 重启恢复后再次同步成功。仓库和 CI 不含本机云配置，跨设备书籍／进度及其他平台真实登录尚未验收。[云接入说明](docs/cloud-setup.md)

EPUB 当前为文字阅读，不是完整图文排版；扫描 PDF 暂不做 OCR。系统 TTS 的后台／锁屏／媒体键还需要逐端真机验证及补充适配，不能据前台播放代码宣称后台能力完成。

## 运行与验证

```sh
flutter pub get
flutter run -d macos
flutter analyze
flutter test
```

其他端：`flutter build apk --debug`、`flutter build ios --simulator --debug --no-codesign`；Windows 在 Windows 主机执行 `flutter build windows --debug`。

已配置的云构建可使用 `--dart-define-from-file=/你的本地路径/cloud-config.json`。配置不提交 Git，不打印令牌。

`.github/workflows/build-apps.yml` 已上传 GitHub，运行结果以仓库 Actions 页面为准；调试包不等于商店签名发布包。

本地体验示例：[本地读听示例](samples/本地读听示例.txt)。

## 文档

- [第一阶段需求 0.3](docs/requirements.md)
- [第一阶段设计 0.3](docs/system-design.md)
- [云配置与已知接入限制](docs/cloud-setup.md)
- [实际进度](docs/PROGRESS.md)

旧商业远景以 v0.2 文档归档，本阶段不执行其中的加密、公共书库和交易功能。正式包标识为 `com.fairyphoenix.bookworm`（旧标识被占用，用户确认更换）。新版独立安装，旧版数据保留，书籍需迁移或重新导入。

## 额度停止约定

每阶段及长任务间使用 `get_usage_limits` 查询；任一适用窗口剩余 ≤5% 时保存进度并停止，不自动使用重置券，见 AGENTS.md。

## 源码仓库与本地签名构建

私有仓库：https://github.com/MikeChongZhou/BookWorm 。

已生成 macOS Release App（Developer ID 签名，未完成 Apple 公证）和 iOS development IPA（仅限描述文件登记设备，不是 App Store 包），详见 [构建记录](docs/builds.md)。安装包保存在本地 dist/，不进入源码 Git 历史。

## 1.0.1：About 与云连接提示

新增参考 STG 的 About（版本、Fairy Phoenix Foundation 署名与版权、使用／隐私说明、可点击许可证）；macOS 菜单接到同一页面。

当前私人云登录仍未配置，页面明确标记“本版本尚未启用登录”并提供说明，不将其显示为账号连接失败。详见 [说明](docs/about.md)。

## 1.0.2：设置、语言与原生私人云

主导航为书架／听书／设置，私人云位于设置内；支持跟随系统（默认）、简体中文、English、Español，保存手动选择并实时更新界面。macOS Settings… 菜单可打开设置。私人云采用账号授权与应用专属容器，无需用户选择同步文件夹。
