# iPhone / iPad 自签安装

Elychron 提供已编译的 Release IPA，iPhone 和 iPad 使用同一个安装包，不需要 Mac、Xcode 或重新编译。
IPA 需要用你自己的 Apple 账号签名后才能安装。下面以 **Windows + iloader** 为例。

## 一、准备文件

- 从 Release 下载 `Elychron-1.5.0.1-ios.ipa`。
- 同时下载 `.ipa.sha256` 文件，用于检查下载是否完整。
- 从 [iloader 官网](https://iloader.app/) 或 [官方 Releases](https://github.com/nab138/iloader/releases/latest) 下载 Windows 安装器。
- Windows 按 [官方说明](https://github.com/nab138/iloader#how-to-use) 先安装 iTunes，准备设备连接所需的驱动。
- 准备数据线、自己的 Apple 账号和 iPhone / iPad；升级前在 Elychron 中导出 JSON 备份。

也可以在 Windows PowerShell 中安装 iloader：

```powershell
winget install --id nabdev.iloader --exact --source winget
```

## 二、签名并安装

1. 用数据线连接手机或平板，解锁设备并确认「信任此电脑」。
2. 打开 iloader，在工具窗口自行登录 Apple 账号并完成验证。不要向开发者发送密码、验证码或证书。
3. 选择设备，导入下载的 Elychron IPA，按窗口提示完成签名和安装。
4. **保留 ShareExtension 和 WidgetExtensions**；删除扩展会让「存到 Elychron」和桌面小组件不可用。
5. 如系统提示未信任开发者，在「设置 → 通用 → VPN 与设备管理」中信任自己的签名账号。
6. iOS / iPadOS 16 及以上按提示开启「设置 → 隐私与安全性 → 开发者模式」，重启并确认。
7. 打开 Elychron，登录学校账号，按需允许通知；原生闹钟还需要 iOS / iPadOS 26+ 和独立的闹钟授权。

## 三、续签与更新

- **免费 Apple 账号签名通常有效 7 天**。iloader 是安装工具，这里不提供自动续签保证；请在到期前重新连接电脑，使用同一账号重新签名安装。
- 到期后需要更新签名，并不需要重新编译 IPA。App 可能暂时无法打开，也不要依赖其继续提醒。
- 同一 Apple 账号、同一实际 Bundle ID 是覆盖安装和保留数据的前提；先备份，再尝试覆盖，不要先删除旧 App。
- 换账号、改 Bundle ID 或更换签名工具可能安装成独立 App；原待办和登录信息不保证自动迁移。

## 四、系统与功能条件

| 功能 | 使用条件 |
|---|---|
| 基础安装 | 构建最低版本为 iOS / iPadOS 15；旧系统完整功能尚未逐项验收 |
| 通知提醒 | 允许通知；显示、声音受通知设置和专注模式影响 |
| 原生闹钟 | iOS / iPadOS 26+，允许闹钟权限；不可用时回退通知 |
| 照片 / 文件分享 | 保留 ShareExtension，并由签名工具保留有效 App Group 共享权限 |
| 待办 / 校园卡小组件 | 保留 WidgetExtensions，并由签名工具保留有效 App Group 共享权限 |
| 普物实验、图书馆等 | 手机自身可访问校园网或学校 VPN；不能继承电脑的校园网络 |

签名工具需保留有效 App Group 权限，才能让主 App、分享扩展和小组件交换数据。认证信息存于系统钥匙串。

## 五、反馈

遇到问题请到项目 Issues 说明：设备系统版本、App 版本 / 构建号、签名工具和错误提示。
诊断日志可从 App 中导出脱敏版本；不要上传密码、验证码、签名证书、配对文件或带登录票据的完整网址。

## 六、文件校验

本版本 IPA 的 SHA-256：

```text
bd046cd77ad53da654b40028c112221d08e6256508b1156576242fa04825b6df
```

Windows PowerShell：

```powershell
Get-FileHash .\Elychron-1.5.0.1-ios.ipa -Algorithm SHA256
```

## 开发者构建

构建和打包见仓库 `docs/ios-port.md` 与 `scripts/package_self_sign_ipa.py`。
发布 IPA 不含个人开发证书、设备授权文件或个人 Team 签名；包内无证书签名不能用于直接安装。
