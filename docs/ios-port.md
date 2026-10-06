# 苹果平台功能与构建

## 平台标注

| 功能 | iOS / iPadOS | Android / 共用范围 |
|---|---|---|
| 每条待办原生闹钟 | **苹果专属：AlarmKit，系统 26+**。时间设置选择「通知／原生闹钟」，保存后生效；改期替换旧闹钟，完成／删除取消。授权拒绝或调度失败回退通知 | Android 默认通知，详情菜单另有手动系统时钟入口 |
| 详情菜单独立闹钟 | 系统 26+ 创建一次性 Elychron 闹钟，不写入 Apple「时钟」，不随待办改期／完成同步 | Android 手动写入系统时钟，同样需独立管理 |
| 宽屏侧边栏 | **iPadOS 适配**：窗口宽度至少 900 逻辑像素使用五栏目侧边栏，内容限宽；窄窗口保留底栏。表单及弹窗避让键盘 | Flutter 共用代码，不需要另做一套 iPad App |
| 分享导入 | **苹果实现：Share Extension + App Group**。「存到 Elychron」保存文字／图片／文件，手动返回 App 选择新建或已有待办；取消时保留收件箱 | Android 使用 Intent，也支持分享导入，不是苹果独占功能 |
| 待办／校园卡小组件 | **苹果实现：WidgetKit**，需扩展及 App Group 签名 | Android 有 AppWidget；小组件不是本轮新增的独占能力 |
| 快捷指令新建待办 | 苹果「快捷指令 → 打开 URL」使用 `elychron://todo/create`；本轮实机入口未完整验收 | URL 处理共用 Flutter 实现，不代表有独立 App Intent 插件 |
| 系统日历、普物实验、PTA、图书馆 | 共用手机功能，需系统权限、网页登录或校园网络 | Android 同样支持，不标为苹果独占 |
| 后台刷新 | iOS 决定任务何时执行，15 分钟是请求间隔，不能保证准点 | Android 后台机制不同，也受系统限制 |

普通通知在 App 前台也会请求显示，实际横幅和声音仍受系统通知设置、专注模式影响。
「已提醒」表示提醒时刻已到，不表示待办自动完成，也不保证用户看到了通知。

## 构建和签名

最低安装版本为 iOS / iPadOS 15；原生闹钟需要 26+。
本轮验证环境为 Flutter 3.47.5、Xcode 27；iPhone 与 iPad 共用 IPA。
先在仓库根执行 `flutter pub get`，再打开 `ios/Runner.xcworkspace`，不是单独的 xcodeproj。

### 仓库标识

| 配置 | 本人 fork | 原作者兼容分支 |
|---|---|---|
| Release 主 App | `com.obladi0617.elychron` | `top.celechron.celechron` |
| Debug / Profile 主 App | `com.obladi0617.elychron.debug` | `top.celechron.celechron.debug` |
| Release App Group | `group.com.obladi0617.elychron` | `group.top.celechron.celechron` |
| Debug / Profile App Group | `group.com.obladi0617.elychron.debug` | `group.top.celechron.celechron.debug` |

WidgetExtensions 和 ShareExtension 使用所属主 App 的标识前缀，并加入相同 App Group。
Flutter Keychain 必须与当前配置的 App Group 一致，Profile 也使用 debug group。
原作者兼容分支保留原有 Bundle ID、Team、签名方式和 provisioning 设置；不要用 fork 的签名文件覆盖它们。

在 Xcode 登录自己的 Apple 账号，为 Runner、WidgetExtensions、ShareExtension 选择同一团队，并配置 App Groups。
个人 Team 和本机 provisioning 不提交。免费 Personal Team 可对自己的已登记设备测试，签名有效期以 profile 为准；广泛分发需要对应发行资格。
无需把密码、验证码或凭据发送到聊天。

### 模拟器与实机

`flutter build ios --simulator --no-codesign` 仅做无签名编译，不能用于判断共享钥匙串登录正常，可能在发请求前出现 `-34018`。
实际登录测试用 Xcode 运行，或先执行 `flutter build ios --debug --simulator --config-only --no-pub`，再构建：

```bash
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES build
```

这是模拟器 ad hoc 签名，不是实机签名。Device Hub 输入需开启 Capture Keyboard 并点击输入框获得焦点；Mac 键盘捕获异常不等于 App 文本框逻辑失败。

`flutter build ios --release --no-codesign` 只生成无签名 Runner.app，不能直接安装。
有效实机归档需要证书、Team、三套 target profile 及测试设备授权。
先执行 `flutter build ios --release --config-only --no-codesign --no-pub`，再用自己的 Team（替换 YOUR_TEAM_ID）归档：

```bash
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath build/ios/archive/Elychron.xcarchive \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates archive
```

在 Xcode Organizer 导出开发测试包，或用 `xcodebuild -exportArchive` 配合自己的 ExportOptions.plist。
Xcode 27 开发测试使用 `method=debugging`、`destination=export`、`manageAppVersionAndBuildNumber=false`。
主 App 与扩展版本均从 Flutter 生成配置读取，本轮未修改 pubspec.yaml 版本。
导出后检查签名、profile 有效期与设备授权，并从这份 IPA 安装验证。

## 合并适配边界

原生实现主要在 `ios/Runner/NativeAlarmBridge.swift`、`ios/ShareSupport`、`ios/ShareExtension` 和 `ios/Runner/ShareStreamHandler.swift`。
iPad 布局在 `lib/design/adaptive_*` 与 `lib/page/tablet/adaptive_home_body.dart`，调用点保持小范围。
新增选项存 optionsBox，不修改 Hive adapter；普物实验使用可移除课程附加层，不写入教务原始 JSON。

未来修改以下部分时保留接入点并复测：

- Xcode target / App Group / Keychain：检查三套 target 与 Debug / Profile / Release，不混用两个仓库的标识和签名。
- 待办保存、重复、完成、删除：保留逐条提醒方式和取消／重排闹钟流程。
- App / Scene 生命周期：保留分享收件箱返回前台时通知 Flutter 的流程。
- Semester 时段生成、Scholar 刷新：保留来源选择和附加层，详见 [普物实验说明](physics-lab.md)。

## 本轮验证记录（2026-10-06）

- fork 和原作者兼容分支：完整 Flutter 测试各 867 条通过；静态分析各 0 error（445 条既有 warning/info）；官网桥接 Node 测试通过。
- fork Release：签名归档、IPA 导出、ZIP 完整性及深度签名验证通过；主 App、分享、小组件版本均为 1.5.0.1+11；已更新安装到连接的 iPhone 17。
- 原作者兼容分支：Debug 模拟器构建通过，扩展版本一致，签名完整性验证通过；保留原作者标识和签名设置。未使用原作者 Team 导出实机 IPA。
- 用户确认本轮功能验收通过；此前明确确认实机照片分享返回 App 会弹出待办选择、通知正常发送、原生闹钟可响。本轮未逐项重做所有苹果入口验收。
- iPad 普物实验官网登录、同步和课表来源选择经用户验收通过。
- 仍需分别验收：快捷指令入口、全部 Widget 内容、系统日历实际导出事件、旧系统通知回退、完整后台刷新。Android APK 本轮未实编及实机验收，见 [Android 编译说明](android-build.md)。
