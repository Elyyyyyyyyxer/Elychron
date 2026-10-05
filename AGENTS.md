# AGENTS.md —— 给代理的硬约束（Elychron 仓库）

> 这份文件是**给 AI 代理看的**（人看的说明在 README.md / MOD_NOTES.md）。
> 每条都是踩过坑换来的：违反一条就出过一次事故。**动手前先读它。**

## 一、绝不做
- **不发布 release**（GitHub / Gitee 都不许），不动 `pubspec.yaml` 版本号，不 force push。
- **任何密钥/口令/token/会话 cookie 都不许写进仓库、日志、聊天**；用户粘贴的凭据用完即弃
  （`.local-secrets.md` 是本地文件，gitignore 已忽略，别去动它、更别提交）。
- **不改 Hive adapter / 字段计数**（历史上写坏过：多一个字段没同步 adapter 会导致 App 打不开）。
  新的持久状态一律存 `optionsBox`（普通键，不动结构）。
- 不替用户做"自动化写操作"（替他预约、提交作业、发布内容…），除非他明确要求。

## 二、提交前必须验证（缺一不可，且要**看到证据**）
1. `flutter analyze --no-pub` → **0 error**（warning/info 可以有，error 不行）。
2. `flutter test --no-pub` → **全绿**（当前基线：798 条）。
3. 构建 → **必须看到 `√ Built ...` 才算成功**。
   ⚠️ 失败时输出里**照样**会打印 `Running Gradle task 'assembleRelease'...`，别被它骗了；
   曾经因此把旧 APK 装到手机上、还把编译不过的代码提交推送了。
4. 命令必须在**仓库根**下跑（`D:\celechron-mod\Celechron`，ASCII junction），
   在上级目录跑会报 "should be run from the root of your Flutter project"。
5. 装机前先找手机地址：`adb mdns services`（换 Wi-Fi 后 IP 会变；无线调试是**按网络**记的）。

## 三、真机操作纪律（血泪）
- **不盲点坐标**：先 `screencap` 看界面、再算坐标；一次只做一件事，做完立刻截图核对。
- 软键盘弹出会把布局整体推上去 → 点按钮前先收键盘（`input keyevent 4`），否则会点到别处。
- **绝不把用户的数据/凭据输入到别的 App**：曾有一次 `adb shell input text <cookie>`
  因为坐标点偏、前台是别的地图/浏览器，把用户的会话 token 输进了别人的搜索框。
- 用户手机上只允许"看自己 App 的界面 + 点自己 App 的界面"。

## 四、界面与文案
- 界面里**不许出现 markdown 语法**（`**`、反引号会原样显示）；脚注**1~2 句**，
  用户明确抱怨过"一大片文字"。
- 统一观感：`design/page_background.dart` 的 `pageBackground`、
  `design/section_text_style.dart` 的 `sectionHeader/sectionFooter`、
  `design/app_accent.dart` 的 `AppAccent`；`AppAccent.primary` 不是 const，别放进 const 表达式。

## 五、汇报纪律
- 只报**亲眼验证过**的；没验证就写"没验证"，**不许**把"应该能用"说成"已验证"。
- 失败要贴关键输出（命令 + 那几行），不要只说"失败了"。
- 提交信息用中文写清**为什么**（不只是做了什么）。
- 推送前 `git status --porcelain` 必须为空；GitHub 经常连不上 → 用后台任务每 60 秒重试（最多 20 次）。
- 推送/构建结果要自己确认（`git rev-parse HEAD` vs `@{u}`；`√ Built`）。

## 六、环境事实
- Flutter：`D:\flutter\bin\flutter.bat`；项目根：`D:\celechron-mod\Celechron`。
- 手机：`adb connect <IP>:5555`（IP 用 mDNS 现查）；包名 `xyz.nosig.celechron.mod`。
- 日志：`libraryTrace()`（lib/http/library_spider.dart）**同时**写文件 + 打 logcat ——
  只写文件的话，代理在电脑上读不到（release 包打不开私有目录）。
- 相关侦察/设计笔记：`docs/CAMPUS_SERVICES_PLAN.md`（图书馆/预约系统）、
  `docs/PTA_RECON.md`、`docs/LIBRARY_RESERVATIONS_SPEC.md`。
