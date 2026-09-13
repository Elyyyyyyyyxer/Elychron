# 公开发布清单（Elychron）

> 目标：把 Elychron 公开发布（首个场景是 CC98 分享），做到**合规、可升级、不冒犯上游**。
>
> 这份文档是**动手清单**，不是设计文档。每条都写清「现状 / 怎么做 / 为什么」。
> 相关：`BACKLOG.md` 第 23 项（发行这条线）、第 13 项（图标）、第 14 项（名字）。

---

## 零、一句话现状

功能层面**已经远超发布门槛**（四种时间语义、子待办行程表、专注计时、AI 整理、
局域网同步都是上游没有的）。剩下的是**工程与合规的收尾**，与功能质量无关。

已核实的事实（2026-09-12）：

| 事实 | 值 | 影响 |
|---|---|---|
| applicationId | `xyz.nosig.celechron.mod` | 与上游 `xyz.nosig.celechron` **不同** → 两个 App 可共存 ✓ |
| 签名 | `signingConfig signingConfigs.debug` | ✗ **必须换**（见 P0-2）|
| 更新检查 | 已改为自己的 GitHub Releases API | ✅ 见 P0-1 |
| 版本号 | `1.4.0-elychron.1+4` | ✅ 见 P1-1 |
| 图标 / `assets/logo.png` | 自己的（爱莉希雅粉，`ed00918`）| ✅ 见 P0-3 |
| LICENSE | GPLv3 | 有义务，见「三、合规」|
| 仓库 | `Elyyyyyyyyxer/Elychron`（public）| ✅ 见 P0-4 |
| minSdk | 28（Android 9+）| 校园机型覆盖率够 ✓ |

---

## 一、P0：不做不能发

### P0-1 改掉上游更新检查 —— ✅ 已完成（2026-09-12）

- **原来是**：`lib/worker/fuse.dart` 里三个 `api.celechron.top/checkUpdate`，
  更新弹窗的「访问网站」指向 `celechron.top`（上游官网）；设置页还有一行
  「前往项目网站」也指向那里。
- **为什么必须改**：上游发版后我们的用户会看到「有新版本」并被引到上游官网 ——
  等于给自己用户做导流；他们从那下到的是**官方包**（包名不同）→ 手机上多出
  第二个应用；而且频繁请求别人的服务器本身不合适。
- **现在**：只认我们自己的仓库 ——
  `https://api.github.com/repos/Elyyyyyyyyxer/Elychron/releases/latest`，
  解析 `tag_name` 与 `body`（说明第一行做摘要）；弹窗按钮改为「去下载」并指向
  Release 页；**没有 Release 时 GitHub 返回 404 → 当作「无更新」安静跳过**；
  设置页那行改成「检查更新 / 项目主页」，同样指向我们的 Release 页。
  仍然一天最多查一次，任何异常都静默（不影响本地功能）。
- 顺带发现并处理：`lib/http/calendar_config_parser.dart` 的
  `calendar.celechron.top` 是**上游的公开校历配置接口**，这是唯一还依赖上游的
  地方 —— 只读、不含用户数据、失败会多级降级（缓存 → 本地推算）。
  已在代码里写明，并写进隐私说明与风险表。

### P0-2 用自己的签名

- **现状**：`android/app/build.gradle` 的 release 用 `signingConfigs.debug`。
- **为什么必须换**：
  - debug 签名的包**以后无法覆盖升级**（除非永远用同一台机器的 debug key）；
  - 部分安全软件/系统会拦「调试签名」；
  - **签名一旦发出去就换不了** —— 换签名 = 用户必须卸载重装 = **待办数据全丢**。
- **怎么做**：见下面「四、签名步骤」。**keystore 必须备份到两处**（丢了就再也发不了升级）。

### P0-3 换成自己的图标与 logo

- **现状**：`android/app/src/main/res/mipmap-*/ic_launcher.png` 与 `assets/logo.png`
  是上游美术。GPLv3 是**版权**许可，**不包含商标授权**。
- **怎么做**（三选一）：
  - (a) 代码生成一个原创几何图标（粉色渐变 + 计时器字形）——零成本、绝对原创；
  - (b) 自己画 / 请人画；
  - (c) AI 生图后规整成 mipmap 尺寸。
- **要替换的清单**：`mipmap-mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi/ic_launcher.png`、
  `assets/logo.png`（关于页那张）。
- 好消息：`assets/logo.png` **不含任何文字**，不存在「新名字配旧字样」的尴尬。

### P0-4 让源码可获取（GPLv3 义务）—— ✅ 已完成（2026-09-12）

- 新仓库：**https://github.com/Elyyyyyyyyxer/Elychron**（public，已推 main + 全部 tag）
- 旧仓库由仓库主自行删除 —— 删掉之后，旧提交与旧名字就不再挂在 GitHub 上了
- **历史已做彻底切割**（`git filter-repo`）：
  - 65 个提交的**作者/提交者元数据**（旧名字 + 旧 noreply 邮箱）→ 全部改成新身份
  - 3 个提交**内容里**出现过旧名字的 blob → 全历史替换
  - README / PRIVACY / 关于页 / 本文档里的旧仓库链接 → 改成新仓库
  - 核验：`git log --all --format='%an%ae%cn%ce'`、`git log --all -S<旧名>`、
    工作区 `git grep` 全部为空 ✓
- ⚠️ **不要改** `lib/utils/data_sync.dart` 里的 `format = 'celechron-mod'`：
  它是**备份/同步文件里的格式标识**，改了会让用户已有的备份文件与旧客户端同步包
  全部被拒绝。它只是「上游项目名 + mod」，**不含任何账号信息**。

---

## 二、P1：强烈建议发布前做

| # | 事 | 说明 |
|---|---|---|
| P1-1 | 版本号与命名 | 建议 `1.4.0-elychron.1`（`pubspec.yaml` 的 version + `versionCode` 递增）。关于页写清「基于上游 v1.3.0」 |
| P1-2 | 修「专注休息提醒锁屏不响」 | 见 `BACKLOG.md` 第 20 项。专注是主打功能，而它最典型的用法就是**锁屏扣在桌上** |
| P1-3 | README 重写 + 截图 | GitHub 首页要有：这是啥 / 与上游的区别 / 怎么装 / 隐私说明 / 反馈渠道 |
| P1-4 | 真机回归一轮 | 老数据升级（P1 已做兼容+单测）、待办页不再卡死（已修）、四种类型各点一遍、专注完整跑一轮、AI 一次 |
| P1-5 | `PRIVACY.md` 复核 | 确认措辞覆盖：AI 可选+自带 key、局域网直连、无自建服务器 |
| P1-6 | 关于页复核 | 现在已有「非官方修改版」声明 + GPLv3 + 源码地址 ✓ 发布前再看一眼版本号 |

---

## 三、P2：可以发布后再说

- **BACKLOG 20**（如果 P1-2 没做）、**21**（死字段迁移）、**22**（按标签分布 / 中断率）
- 高德导航时间计算（BACKLOG 19）—— 属于新功能，别塞进首发
- 外观统一 / 壁纸（BACKLOG 5）、Windows 桌面端（BACKLOG 4）

---

## 四、签名步骤（只有仓库主本人能做）

### 0. 记录：证书指纹（**已生成，2026-09-13**）

```text
DN       : CN=Elychron, O=Elychron, C=CN
SHA-256  : b2cc42560a1378b9087c7660ff9904c1cef5cb89a12f5eba68faa98a93a771c8
SHA-1    : ba4ee7956f02c57f419d3ef20836f70c9c66ba42
keystore : D:\keys\elychron-release.jks（仓库之外，PKCS12，别名 elychron，有效期 10000 天）
```

- 以后每次发版都用 `apksigner verify --print-certs` 核对 **SHA-256 是否仍是这一串** ——
  对不上就说明用错 keystore 了（那会导致老用户无法覆盖安装）。
- keystore 与密码**各备份两处**：丢了 = 所有用户只能卸载重装（待办数据丢失）。
- 生成脚本：`tools/setup_signing.ps1`（keystore + `android/key.properties` 一步到位；
  带 `-DryRun` 只预览，支持 `-StorePass` 非交互，且 **stdin 被重定向时会直接报错而不是等输入**）。

### 1. 生成 keystore（已完成，保留原始命令备查）

```powershell
# 选一个不在仓库里的目录存放（例如 D:\keys\），密码自己想好
keytool -genkeypair -v `
  -keystore D:\keys\elychron-release.jks `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 `
  -alias elychron
```

> ⚠️ **证书里的身份信息（DN）要中性**：`CN` / `O` 一律填 `Elychron`（或直接回车跳过），
> **不要填真实姓名、学校邮箱或任何与本人相关的信息**。这个 DN 会写进 APK 的签名证书，
> 任何人用 `apksigner verify --print-certs` 或 `keytool -printcert` 都能看到 —— 它是公开信息。

### 2. 写 `android/key.properties`（**这个文件已在 .gitignore，不入库**）

```properties
storePassword=你的store密码
keyPassword=你的key密码
keyAlias=elychron
storeFile=D:/keys/elychron-release.jks
```

### 3. `android/app/build.gradle` 里接上

```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties['keyAlias']
                keyPassword = keystoreProperties['keyPassword']
                storeFile = file(keystoreProperties['storeFile'])
                storePassword = keystoreProperties['storePassword']
            }
        }
    }
    buildTypes {
        release {
            // 有 key.properties 就用正式签名；没有就退回 debug（本地调试仍然能构建）
            signingConfig keystorePropertiesFile.exists()
                ? signingConfigs.release : signingConfigs.debug
        }
    }
}
```

### 4. 验证签名

```powershell
# 应该看到 CN=... 而不是 Android Debug
& "C:\Android\Sdk\build-tools\36.0.0\apksigner.bat" verify --print-certs `
  build\app\outputs\flutter-apk\app-release.apk
```

> ⚠️ **keystore + 密码必须备份两处**（比如私有网盘 + 移动硬盘）。
> 丢了 = 老用户永远无法覆盖升级，只能卸载重装（数据丢失）。

---

## 五、构建与产物

```powershell
# 必须从 ASCII junction 构建（中文路径会让 Gradle 报 non-ASCII）
cd D:\elychron\Elychron   # 用你自己的仓库目录（必须不含中文）
cmd /c "D:\flutter\bin\flutter.bat build apk --release --target-platform android-arm64 --no-tree-shake-icons"
```

- 产物：`build\app\outputs\flutter-apk\app-release.apk`（约 25 MB）
- 只出 arm64：校园机型覆盖率足够；如果要给老机型，再加 `android-arm`
- 发布**不要**用 `--split-per-abi`（一个包最省事）
- 单测与静态检查必须全绿再发：`flutter analyze`（0 error）+ `flutter test`

---

## 六、发布步骤

1. **打 tag**：`git tag v1.4.0-elychron.1 && git push origin v1.4.0-elychron.1`
2. **GitHub Release**：附上 APK，写清「与上游的区别」「已知问题」「安装方法」
3. **检查清单**（每次发版都过一遍）：
   - [ ] `flutter analyze` 0 error
   - [ ] `flutter test` 全绿
   - [ ] 版本号已递增（`pubspec.yaml` 的 version + versionCode）
   - [ ] APK 用**自己的签名**（`apksigner verify --print-certs` 看过）
   - [ ] 关于页显示的版本号与实际一致
   - [ ] 更新检查不指向任何上游域名
   - [ ] 真机装一次、升级装一次（旧版本 → 新版本，数据还在）
4. **发布后**：帖子里只放 GitHub Release 链接，不要在论坛收 bug（会沉）。

---

## 七、CC98 发帖模板

> **先看板规**：确认该板是否允许发外链 / 直接发 APK（有的板要求走附件或网盘）。

**标题**
```
Elychron —— Celechron 的非官方改版（四种时间语义 / 子待办行程表 / 专注计时 / AI 整理）
```

**正文结构**

1. **一句话定位**
   非官方修改版，重点解决三个痛点：**备忘天天过期**、**活动提醒错位**、
   **敲代码没法计入时间**。永久免费、无广告、无自建服务器。

2. **和官方的区别**（表格）
   | 维度 | Elychron | 官方 Celechron |
   |---|---|---|
   | 时间语义 | 活动 / 截止 / **提醒** / **备忘** 四类，各有独立提醒锚点 | 只有 DDL + 日程 |
   | 子待办 | **行程表**：带时间地点、每步单独提醒、时间轴 | 勾选清单 |
   | 专注计时 | 60/15 可调、落库、统计页 | 无 |
   | AI | 分享消息/截图→待办、划分类型、拆带时间的行程 | 无 |
   | 电脑端 | 局域网同步 + 浏览器面板 | 无 |

3. **截图**：5~8 张（日程 / 待办卡片 / 详情页四胶囊 / 子待办时间轴 / 专注大圆 /
   专注记录 / AI 整理预览）

4. **安装**
   - 下载 APK → 允许「未知来源」安装
   - ⚠️ **包名与官方不同，可以和官方版同时装在一台手机上**，数据互不影响，
     先装着对比，不喜欢直接卸载

5. **隐私与安全**（一定会被问，先说）
   - **没有自己的服务器**，不上传任何数据
   - 教务网账号密码只存本地系统密钥库，直连学校服务器
   - AI **默认关闭**，开启后用**你自己填的** API key 直连服务商
   - 局域网同步只在同一 Wi-Fi 内直连，不经过任何中转
   - 校历/考试周/假期这份配置来自上游 Celechron 的公开接口
     `calendar.celechron.top`（只读公开校历，不含任何个人信息；
     连不上会自动用缓存或本地推算）
   - 更新检查只请求我们自己的 GitHub Releases
   - 源码公开可查（链接）

6. **免责**
   非官方，与学校及上游项目无关；免费且无广告；使用风险自负。

7. **反馈**：GitHub Issues（附链接）

---

## 八、已知风险与对策

| 风险 | 对策 |
|---|---|
| **会被问「会不会封号」** | 说明只做只读抓取 + 与官方客户端相同的登录方式；不代替用户做任何写操作（除非教务网本身支持）；帖子里给源码位置让人自查 |
| 上游要求改名/下架 | 名字已与上游无冲突（Elychron）、声明非官方、源码合规；保留随时改名的余地 |
| 用户数据丢失投诉 | 首次发布就定签名；README 教用户「导出数据」做备份（设置 → 数据 → 导出）|
| 新版引入回归 | tag 之前跑全量单测 + 真机回归；Release notes 写清已知问题 |
| 校园网/接口变更导致抓取失败 | 应用本身有诊断日志（设置 → 诊断与测试），先教用户导出日志再排查 |
| **依赖上游的校历配置接口** (`calendar.celechron.top`) | 这是唯一还依赖上游的地方：只读、不含用户数据、失败会降级到缓存/本地推算。若上游关停或明确反对，改 `calendar_config_parser.dart` 里那一个常量即可（自建或随包内置）|
| 被当成「官方」 | 关于页 + 帖子里双重声明「非官方」；不要在标题写「浙大官方」等字样 |

---

## 九、发布前最后一跳（把这份文档当 checklist 用）

```
[x] P0-1 更新检查改指向自己的 GitHub Releases（弹窗与设置页都不再指上游）
[ ] P0-2 keystore 生成（DN 用中性信息）+ 签名接上 + apksigner 验证 + 备份
[x] P0-3 图标与 logo 换成自己的（2026-09-11 `ed00918` 爱莉希雅粉，已确认与上游不同）
[x] P0-4 新仓库 Elychron 已建 + 历史身份已切割（旧仓库由仓库主删除）
[x] P1-1 版本号 1.4.0-elychron.1（pubspec + `Fuse.appVersionName`/`version` 三处同步）
[x] P1-2 专注锁屏提醒修掉（已排进系统，dumpsys alarm 验证过）
[ ] P1-3 README 重写 + 截图
[ ] P1-4 真机回归（含覆盖安装升级）
[ ] P1-5 PRIVACY.md 复核
[ ] P1-6 关于页版本号复核
[ ] 打 tag v1.4.0-elychron.1 + GitHub Release（附 APK）
[ ] CC98 发帖
```
