# 用户自签安装（Release 交付）

## 交付文件

`Elychron-1.5.0.1-self-sign.ipa` 是已编译的 Release 程序，用户无需 Xcode 或重新编译源码。
主 App、分享扩展、小组件均保留；没有个人开发证书、Apple Team 标识或设备 provisioning profile。
包内 ad hoc 签名仅保留 AltStore 识别能力所需的 App Group 声明，**不能直接安装**，必须用用户自己的账号重新签名。
用同目录 `.ipa.sha256` 文件核对下载完整性。当前只准备本地文件，没有发布 GitHub Release。

## 首选验收工具：AltStore Classic

AltStore Classic 与 AltStore PAL 是不同安装渠道，这里的 IPA 使用 Classic 自签。
先按官方 [macOS 安装步骤](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos) 或 [Windows 安装步骤](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) 安装 AltServer 和手机上的 AltStore。

1. iPhone / iPad 连接电脑、解锁并信任；按工具说明启用开发者模式及设备信任。
2. 在 AltServer 和 AltStore 的登录窗口自行输入 Apple 账号，不向开发者提供密码或证书。
3. 将本版本 IPA 保存到手机「文件」，在 AltStore 的 My Apps 点 `+` 导入。
4. 若工具询问扩展，**保留 ShareExtension 与 WidgetExtensions**；删除后照片分享及小组件将不可用。
5. 安装完成后打开 Elychron，按需重新登录学校服务，授权通知；使用原生闹钟还需系统 26+ 的闹钟权限。

免费账号的应用通常每 7 天需刷新签名；AltServer 需能与手机连通，定期打开 AltStore 检查刷新状态。
Elychron 含主 App 与两个扩展，需 3 个 App ID，另加 AltStore 自身占用；免费账号的 App ID 数量和过期规则见 [官方说明](https://faq.altstore.io/altstore-classic/app-ids)。
不在此版本保证 Sideloadly、SideStore 或其它工具的完整能力，分别实测通过后再标注支持。

## 数据和平台限制

- 同一账号、相同自签标识的续签可以作为升级路径；换账号、改包名或由先前 Xcode 安装切换到 AltStore 时，可能安装成独立 App，不能保证原容器和钥匙串自动迁移。先从旧 App 导出 JSON 备份，保留旧 App，再导入新 App。
- 校园认证信息仍存于系统钥匙串；不因为自签而改存明文。换签名后无法读取旧凭据时，应重新登录。
- AltStore 写入的分组供主 App、分享和小组件共同使用；缺少共享组时普通钥匙串登录可走私有组，分享或小组件不能宣称可用。
- App 启动时实际检查共享钥匙串的读写权限；爱思等工具删除共享权限后，登录改用系统私有钥匙串。照片分享和小组件仍需要签名工具保留有效 App Group 权限。
- 普物实验、图书馆等内网服务需要手机自身的校园网或学校 VPN；不能继承 Mac 的代理。
- 到期是用户签名到期，不是下载的 IPA 文件失效；刷新失败时需检查 AltStore 和设备连接。

## Release 验收清单

- 安装并启动；学校登录和重启后会话恢复。
- 新建、编辑、完成待办，逐条通知／原生闹钟；修改与删除取消原生闹钟；到点卡片显示已提醒。
- 从照片分享，返回 Elychron 能新建或追加附件；重复打开不重复导入。
- 待办小组件与校园卡小组件能读取数据，主 App 更新后可刷新。
- 普物实验同步、来源选择及切回教务，iPhone / iPad 布局可操作。
- 同账号重新刷新签名或重新导入 IPA 后，已有待办与设置保留。

2026-10-06：动态分组回归、Flutter 测试、原生分享测试、模拟器构建和 Release 归档已验证；脱敏包的 ZIP、签名及能力检查通过。
**本轮以模拟器验证为验收门槛。AltStore 实际签名、安装、续签和上述实机清单尚未验收；文件不标为完整实机验证通过，也不发布 Release。**

## 开发者重新打包

按 [苹果构建说明](ios-port.md) 生成 Release 归档后，在仓库根使用 Python 3.11+：

```bash
python3 scripts/package_self_sign_ipa.py \
  build/ios/archive/Elychron.xcarchive/Products/Applications/Runner.app \
  dist/Elychron-1.5.0.1-self-sign.ipa
python3 test_native/self_sign_package/check.py dist/Elychron-1.5.0.1-self-sign.ipa
```

脚本复制 App 后处理，不修改输入归档；保留两个扩展，移除个人 profile / 证书文件和 AltStore 个人元数据，重新生成无证书 ad hoc 签名及 SHA-256。
若输出文件已存在，选择新的文件名，不覆盖已有交付。校验失败时不交付、不发布。
检查器根据主 App 的包名核对共享组，fork 和原作者包均可使用。
