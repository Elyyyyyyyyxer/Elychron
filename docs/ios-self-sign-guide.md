# iPhone / iPad 安装 Elychron（自签教程）

我们没有苹果开发者账号，所以 iOS 版不能直接从网页点一下安装。做法是你用自己的 Apple 账号给它签一次名，装到自己手机上——这一步叫"自签"。下面是从零开始的完整流程，不需要 Xcode，也不需要懂编程。

先说清楚代价，免得你装到一半才发现。免费 Apple 账号签出来的应用 7 天后会打不开，需要重新签一次（数据还在，不是重新安装）；付费开发者账号 688 元一年，签一次能用一年。免费账号同时最多只能有 3 个应用标识，Elychron 占 3 个（主应用、分享扩展、小组件），加上 AltStore 自己那一个会接近上限。Elychron 的普物实验与图书馆这类校内服务，需要手机自己在校园网或学校 VPN 里，不能借电脑的代理。

## 准备

一台电脑（Windows 或 macOS 都行）和数据线，一个 Apple 账号（免费的 iCloud 账号就行），一个 IPA 文件。推荐用 AltStore Classic 自签：它由装在电脑上的 AltServer 和装在手机上的 AltStore 两部分组成。官方安装说明：macOS 见 https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos ，Windows 见 https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows 。

## 步骤

1. 在电脑上安装 AltServer，打开后它会常驻在任务栏（Windows）或菜单栏（macOS）。
2. 用数据线连上 iPhone 或 iPad，手机上点"信任此电脑"。
3. 在 AltServer 菜单里选 Install AltStore，选中你的设备，然后输入你自己的 Apple 账号。密码只填在你自己电脑上，我们不会也不需要你的账号密码。
4. 手机上会出现 AltStore 图标。首次打开若提示"不受信任的开发者"，进 设置 → 通用 → VPN 与设备管理 信任你的证书；iOS 16 起还要在 设置 → 隐私与安全性 里打开开发者模式并重启手机。
5. 把 Elychron 的 IPA 存到手机的「文件」App（微信、AirDrop、网盘都行）。
6. 打开 AltStore → My Apps → 右上角加号 → 选那个 IPA。
7. 如果它问要不要保留扩展，两个都保留：ShareExtension 和 WidgetExtensions。删掉的话照片分享和桌面小组件就不能用了。
8. 装完打开 Elychron，重新登录学校服务、授权通知。想用原生闹钟需要 iOS 26 及以上，并在系统里给闹钟权限。

之后每隔一段时间打开 AltStore 看 My Apps 里的过期倒计时，快到期时用 AltServer 刷新一次签名（手机和电脑在同一 Wi-Fi 下、AltServer 开着就行）。

## 常见问题

装的时候报错或者一直转圈，多半是电脑上的 AltServer 没开、手机和电脑不在同一 Wi-Fi、或者 iOS 没打开开发者模式，先把这三样确认一遍。

7 天后打不开是签名过期，不是应用坏了，重新刷新签名即可，数据和登录状态都还在。

换了 Apple 账号、或者从 Xcode 安装切到 AltStore，可能被当成一个新应用装上去，旧容器和钥匙串里的登录信息不保证迁移。稳妥做法是装之前先在旧版本里用「设置 → 导出数据」留一份 JSON 备份，旧应用先别删。

登录一直失败或小组件读不到数据：有些签名工具（例如爱思助手）会去掉共享钥匙串权限。Elychron 启动时会实际检查这个权限，读不到就改用系统私有钥匙串，登录通常还能走；但照片分享与小组件需要共享组，这种情况下不可用。用 AltStore 保留扩展权限一般不会遇到。

校园服务连不上时，先确认手机自己在校园网或学校 VPN 里。

## 打包给别人的话

维护者视角的交付说明在 docs/self-sign-ios.md（脱敏包生成、校验、验收清单），打包脚本是 scripts/package_self_sign_ipa.py。

现状说明：仓库里已具备 Release 归档与脱敏 IPA 打包能力，但尚未正式发布 Release，实机自签与续签流程也还没走完完整验收。上面的步骤按 AltStore Classic 官方流程写成，你实测中发现出入欢迎回报。
