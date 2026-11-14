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
