# GitHub Actions 自动分发

Android、macOS、Windows 安装包全部在 GitHub 托管 runner 上从源码编译，不上传本地编译的安装包。iOS 的 TestFlight 流程本次不变。

维护 `release/platforms.json` 的实际平台版本、构建号和新发布标签，上传源码后推送对应 `apps-buildN` 标签，自动启动 `Release BookWorm apps`。也可以在 Actions 页面手动运行。三端全部成功后，工作流自动创建或更新同标签 Release，并发布三个包及 SHA256SUMS.txt。任一端失败，不执行发布步骤；修复同一批发布时不重复滚动版本。已有下载附件不会在失败时被删除。

首次需要在仓库 Settings → Secrets and variables → Actions 配置以下加密 Secrets：

| Secret | 内容 |
|---|---|
| CLOUD_CONFIG_WINDOWS | Windows 云应用配置 JSON，已配置 |
| CLOUD_CONFIG_ANDROID | Android 云应用配置 JSON |
| CLOUD_CONFIG_APPLE | macOS 云应用配置 JSON |
| ANDROID_KEYSTORE_BASE64 | 现有 Android 签名 keystore 的 Base64 |
| ANDROID_KEYSTORE_PASSWORD | keystore 密码 |
| ANDROID_KEY_PASSWORD | 签名密钥密码 |
| ANDROID_KEY_ALIAS | 现有签名别名 |
| MACOS_P12_BASE64 | 仅 BookWorm 所需 Developer ID 签名证书及私钥的加密 P12 Base64 |
| MACOS_P12_PASSWORD | P12 加密密码 |
| MACOS_PROFILE_BASE64 | BookWorm 专属 Developer ID provisioning profile Base64 |

签名私钥是敏感凭据，首次传入 GitHub 需要单独授权。不要上传整个钥匙串、读者书籍、云登录令牌，或将配置写进源码。凭据只在 runner 临时目录使用，完成后清理；构建产物上传步骤只接收指定安装包。

Android 沿用原测试签名以保持覆盖安装兼容；macOS 为 Developer ID 签名但尚未公证；Windows 为未签名便携包。GitHub 工作流写入权限拥有者可能通过修改工作流使用仓库 Secrets，应限制仓库写入权限。

## Windows 独立正式包

`Release Windows app`（build-windows.yml）可在 Actions 手动启动，或推送与 Windows 清单一致的 `windows-v版本-build构建号` 标签自动启动。它仅编译 Windows Release，带私人云配置与 Release CRT，在 CI 检查所有原生二进制无 Debug CRT 依赖并启动实际 exe，通过后自动发布 GitHub Release。普通 `Build BookWorm apps` 的 Debug artifacts 仅供开发，不用于用户安装。Windows 版本单独维护，其他三端不因这次 Windows 包修复而升级。
