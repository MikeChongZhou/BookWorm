# About 与私人云连接说明

版本：1.0.1 (2)

## 关于页面

参考 STG 的 About 内容组织，新增四端共用的 About 页面：应用名、运行包真实版本／构建号、开发者和版权、使用说明、隐私、当前版本边界、第三方许可证及项目反馈链接。

用户已确认开发者与版权信息沿用 **Fairy Phoenix Foundation**。入口在书架顶部“关于书虫”；macOS 菜单“About BookWorm”转到同一页面。版本使用 package_info_plus 读取，不写死为某次构建号。

第三方声明提供 Flutter 自带的 LicensePage，显示构建时收集的许可原文；另附 Flutter、Dart、PDFium、pdfrx 和 Apple 平台 Swift 的可点击许可证链接。不把未使用的 SQLite／.NET 组件从 STG 照搬到 BookWorm。

外链打开失败时保留地址并可复制，不以无响应按钮结束。

## 私人云为何不能连接

已交付 1.0.0 的构建没有传入真实云应用参数；代码在 `CloudProvider.configured == false` 时拦截连接，还未进入账号授权。这不是用户云账号密码错误或已经确认的网络故障。

- OneDrive：缺 BookWorm 的 Microsoft 原生客户端注册／client ID 和相应端回调验证。
- Google Drive：缺 BookWorm 各平台 OAuth client、Android 所需服务端 client 或注册资源、Apple 回调 scheme 等。
- iCloud：缺 BookWorm 的 CloudKit container、Web Services API token、用户登录回调和生产 schema；四端登录还需专项验证。

SDK 代码与模拟 API 测试存在，不等于开发者应用已注册，也不等于真实云同步已验收。

1.0.1 改进：未启用的云服务显示“本版本尚未启用登录”，操作为“查看说明”，不再展示看似可以直接登录的连接按钮；说明明确无需更换账号，本地功能仍可使用。配置详情见 [云接入说明](cloud-setup.md)。本轮没有凭空填入 client ID，也没有借用 STG 的云应用身份。

下一步是完成 BookWorm 自己的三家云应用注册、回调和真机授权，再构建真正启用云登录的版本；此变更没有把连接问题标记为已修复。
