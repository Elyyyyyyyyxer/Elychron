# Android 重新编译

## 环境

在 Elychron 仓库根目录（包含 `pubspec.yaml`）操作。推荐纯英文路径，尤其是 Windows。
本轮使用 Flutter 3.47.5 / Dart 3.13.4；保留仓库的依赖锁文件，不需要先升级依赖。

| 项目 | 当前配置 |
|---|---|
| 安装系统要求 | Android 9+（minSdk 28） |
| Android Gradle Plugin | 8.13.2 |
| Gradle Wrapper | 8.14.3，自动下载，不必全局安装 Gradle |
| Kotlin | 2.2.20 |
| 构建 JDK | 推荐 JDK 17；源码编译目标 11 不代表能用 JDK 11 运行 Gradle |
| SDK / NDK | 跟随 Flutter；Flutter 3.47.5 使用 SDK 36、NDK 28.2.13676358 |

按 [Flutter 官方 Android 配置说明](https://docs.flutter.dev/platform-integration/android/setup) 安装 Android Studio、SDK Platform、Build-Tools、Command-line Tools、Platform-Tools 及所需 NDK。
JDK 要求见 [AGP 官方兼容表](https://developer.android.com/build/releases/agp-8-13-0-release-notes?hl=en)。
Android Studio 内置 JDK 也可使用，但先用 `flutter doctor -v` 确认 Flutter 实际选用的 Java。

macOS 可在安装 JDK 17 后执行：

```bash
flutter config --jdk-dir "$(/usr/libexec/java_home -v 17)"
flutter config --android-sdk "$HOME/Library/Android/sdk"
flutter doctor --android-licenses
flutter doctor -v
```

Windows 可在安装后配置自己的实际路径：

```powershell
flutter config --jdk-dir "C:\Program Files\Java\jdk-17"
flutter config --android-sdk "$env:LOCALAPPDATA\Android\Sdk"
flutter doctor --android-licenses
flutter doctor -v
```

SDK 许可需构建者自行阅读确认。`android/local.properties` 是本机路径配置，不提交；可包含 `sdk.dir` 与 `flutter.sdk`。

## 每次更新代码后

```bash
flutter pub get
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons --no-pub
```

`--no-tree-shake-icons` 保留仓库既有的 Windows 图标裁剪兼容参数。
必须看到命令成功退出及 `Built ...app-release.apk`，仅出现 `Running Gradle task` 不算成功。
产物：`build/app/outputs/flutter-apk/app-release.apk`。

若要同时生成多种 CPU 架构的安装包，将构建命令换成：

```bash
flutter build apk --release --split-per-abi --no-tree-shake-icons --no-pub
```

各架构 APK 在同一输出目录。没有构建异常时不必执行 `flutter clean`；修改 SDK、Gradle 或插件后遇到缓存异常，再 clean、pub get、重新构建。

## 签名与覆盖安装

`android/app/build.gradle` 会读取被忽略的 `android/key.properties`：
`storeFile`、`storePassword`、`keyAlias`、`keyPassword`。使用自己既有的 keystore，不把文件或密码提交到 GitHub。
没有该配置时，Release APK 自动使用本机 debug keystore，适合本地测试。

覆盖安装需要与已安装 Elychron **相同的应用包名和签名证书**，并且版本号不低于原安装。
不同电脑的 debug keystore 通常不同；自己重编译的包也不能直接覆盖原作者正式签名的发行包。
不要为解决签名冲突直接卸载应用；先在 App 导出 JSON 备份，再决定迁移方式。

连接并授权 Android 测试机后，选择 `adb devices` 中的设备编号：

```bash
adb devices
adb -s <设备编号> install -r build/app/outputs/flutter-apk/app-release.apk
```

当前 applicationId 为 `xyz.nosig.celechron.mod`，与 Celechron 官方版不同。
用 SDK Build-Tools 的 `apksigner verify --print-certs <APK路径>` 核对证书，Mac 上用 `shasum -a 256 <APK路径>` 记录包校验值。

## 平台功能与本轮验证范围

普物实验、PTA、图书馆、待办和课表共用 Flutter 实现；Android 原生分享继续使用 Intent。
苹果的 AlarmKit、Share Extension 和 WidgetKit 不需要加入 Android 工程。
普物实验实机须自身能访问校园内网，不能依赖 Mac 模拟器的代理配置。

2026-10-06：共用代码完整 Flutter 测试 867 条通过、静态分析 0 error。
本轮 Mac 尚未配置 Android SDK / JDK，**没有重新编译 APK，也没有完成 Android 实机验收**。
iOS 模拟器或 IPA 构建成功不能替代 Android 构建验证。
