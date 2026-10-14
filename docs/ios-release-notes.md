# Elychron 1.5.0.1 · iOS / iPadOS

这是 Elychron 的 iOS / iPadOS Release 安装包，两种设备共用一个 IPA。
无需 Mac 或 Xcode，Windows 用户可用 iloader 和自己的 Apple 账号签名安装。

## 下载哪个文件

- `Elychron-1.5.0.1-ios.ipa`：iPhone / iPad 安装包。
- `Elychron-1.5.0.1-ios.ipa.sha256`：下载校验值。
- `SELF_SIGN_GUIDE.md`：iloader 安装、续签和权限说明。

本包不含个人证书或设备授权文件，**需要自签，不能直接点击安装**。
免费 Apple 账号签名通常有效 7 天，到期前需重新签名。

## 本版功能

- **iPad 适配**：宽屏侧边栏，窄窗口保留底栏，表单和弹窗适配平板。
- **逐条选择提醒方式**：设置时间时选择通知或原生闹钟；原生闹钟需要系统 26+，随待办改期、完成或删除调整，不可用时回退通知。
- **照片 / 文件分享导入**：「存到 Elychron」保存后返回 App，可新建待办或追加到已有待办。
- **待办 / 校园卡小组件**：需保留扩展和有效 App Group 共享权限。
- **普物实验课表**：官网登录后同步已选实验，在教务与实验系统间选择最终课程来源，不额外创建待办。
- **保留共用功能**：PTA、图书馆、系统日历导出、待办和 JSON 备份等；需要对应账号、权限或校园网络。

## 安装与更新

使用 iloader 导入 IPA，保留 ShareExtension 和 WidgetExtensions，按提示完成信任和开发者模式设置。
已安装用户先导出 JSON 备份，使用同一账号与实际 Bundle ID 尝试覆盖安装。

## 系统与兼容性

- 构建最低版本为 iOS / iPadOS 15，原生闹钟需要 26+。
- 分享导入和小组件需要签名工具保留扩展及有效 App Group 共享权限。
- 系统日历实际导出、全部小组件、快捷指令、旧系统和续签保留数据尚未逐项验证。
- Android 安装包请从 Android Release 下载。

## 对应源码与校验

此 IPA 的精确源码提交：
[e73c451](https://github.com/Elyyyyyyyyxer/Elychron/commit/e73c45140abb8ed2e251145ecd1b98620ae30215)。
GPLv3，保留原项目版权与许可证声明。

SHA-256：

```text
bd046cd77ad53da654b40028c112221d08e6256508b1156576242fa04825b6df
```
