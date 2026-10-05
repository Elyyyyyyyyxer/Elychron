# 通知与免打扰：真机排查记录（2026-09-29）

用户三条反馈：

> 「手机端问题在于一天会给我推送很多次那个通知，然后我本来应该有的消息提醒就没有了，
> 不知道怎么回事。」
> 「设置界面（好像设置页面延伸的一些子页面也有）的背景底色好像还是会有一层灰色，
> 跟其他页面不搭配，请删掉。」
> 「电脑端的同步刷新应该在获得焦点的时候自动刷新，对吧？」

## 一、「消息提醒没有了」到底发生了什么

**结论：不是通知丢了，是手机被切进了「仅允许闹钟」的免打扰，
所有微信/钉钉的通知都被系统静默了。**

证据全在系统的通知服务日志里（这些命令以后排查同类问题还能用）：

```powershell
adb connect <手机>:5555
adb shell dumpsys notification --noredact > C:\temp\notif.txt
```

在 `notif.txt` 里能直接看到免打扰的开/关流水，以及**哪一条通知被静默了**：

```
09-29 11:46:07.788 set_zen_mode: alarms,setInterruptionFilter
09-29 16:19:37.733 set_zen_mode: alarms,setInterruptionFilter
09-29 16:20:21.708 intercepted: 0|com.tencent.mm|-966079312|null|10185,alarmsOnly
09-29 16:30:07.466 intercepted: 0|com.tencent.mm|-941944751|null|10185,alarmsOnly
09-29 16:58:53.234 intercepted: 0|com.tencent.mm|-941944751|null|10185,alarmsOnly
09-29 17:01:15.513 set_zen_mode: off,setInterruptionFilter
```

`16:19:37 → 17:01:15`（约 42 分钟，正好一个「专注 45 分钟 / 休息 5 分钟」的工作段）
里，微信的十几条通知全部带上了 `alarmsOnly` —— 也就是**只进通知栏、不响不震不弹**。
`17:01:15` 那条 `set_zen_mode: off` 正是 Elychron 的专注结束时还原档位。

也就是说：这件事的源头是 **「专注时自动免打扰」** 这个开关（设置 → 免打扰那一栏）。
它按设计把专注期间的免打扰切成最狠的一档，结束后还原。

**这不是 bug，但它是个"用户不知道自己在被静音"的设计**。给用户的选择：

1. 把这个开关关掉（专注时长照常计时，只是不静音）：
   设置 → 「专注时自动免打扰」；
2. 或者把档位从「完全静音」改成「仅优先」（收藏联系人/重复来电仍能响）；
3. 或者至少让它在专注页上**显眼地说明"现在正在静音"**。

⚠️ 排查时的两个坑（都验证过）：

- 免打扰是**系统级**状态：`adb shell settings get secure zen_mode` 在华为上返回 `null`，
  要看 `adb shell dumpsys notification --noredact | Select-String mZenMode`；
- `dumpsys notification` 的 `enabler=` 字段在 EMUI 上**不太可信**：
  我们代码只设置过 `filterNone(4)`，日志里却写成 `ZEN_MODE_ALARMS`。
  判断"是不是我们干的"要看**成对的出现**（切走 + 稍后还原成 off）。

## 二、「一天推很多次那个通知」怎么修的

那句开场白（原来叫「首次成绩推送已开启」）原来挂在**后台任务**里 ——
WorkManager 每 15 分钟跑一次（`dumpsys jobscheduler` 实测 `Minimum latency: +14m59s`），
一天最多 96 次。它靠 `FlutterSecureStorage` 里的一条记录判断"说过了"，
而**后台 isolate 读加密存储不一定成功**（要过 Keystore，取不到时返回 `null` 而不是报错），
记录一丢就再弹一次。

改法（两层）：

1. **开场白挪到前台**：`showGradePushIntroOnce()`（`lib/worker/background_app_refresh.dart`），
   由 `main.dart` 启动钩子调用，只在用户开着「推送成绩变动」时说一次；
2. **后台只发真正的新消息**，并且去重状态改存**普通文件**
   （`lib/worker/notification_dedup.dart`，和刷新锁 `RefreshCoordinationStore` 同一套思路）——
   不管哪个 isolate 读到的都是同一份。同内容 6 小时内绝不重发；
   作业截止提醒的"已提醒 id"也从加密存储搬到了同一个文件里。

## 三、页面底色的统一

手机端原来只有"设置"这一条线走 `systemGroupedBackground`（`#F2F2F7`），
而日程/待办/专注是白底卡片 —— 实测取样：日程页 `#FDFDFE`，设置页 `#F2F2F7`。

现在 `pageBackground()` **全平台统一**返回 `systemBackground`（浅色白、深色黑），
并且把学业那边的子页面（课程/成绩/考试/培养方案/实践分）以及待办的编辑、
新建页里硬编码的同一层灰一起换掉了。底部弹窗（登录、课程代码映射）
保留灰底 —— 那是弹窗自己的观感，不属于"页面底色"。

## 四、2026-10-01：开场白又问了一次（第二次修）

用户：「Elychron 始终时不时给我推『成绩推送已开启』的通知，不知道为什么」。

真机取证（不是猜）：

- 08:32:01 覆盖安装（`dumpsys package` 的 lastUpdateTime）；
- 08:39:08 那条通知**又发了**（`dumpsys notification` 里的 when=1790815148034）；
- 关键证据：**正文里没有「已经查到 N 门出分」那句** —— 那两句事实是从
  `FlutterSecureStorage` 读的，读不到才不显示。也就是说当时密钥库里
  `gpa` / `gradedCourseCount` 已经是空的：**覆盖安装把密钥库读空了**
  （不少 ROM 就这样，`database_helper.dart` 里那个 `secureStorage.readAll`
  的三秒超时兜底就是为同一个坑加的）；
- 而 08:41 再冷启动一次**没有**重发 —— 说明 08:39 那次把标记重新写回去之后，
  记录又能正常读到，直到下一次覆盖安装。

结论：这条通知的"说过了"当时只记在**密钥库 + 临时目录**，而这两处恰恰都会丢
（密钥库覆盖安装后读空、App 缓存会被清），所以每次覆盖安装都会复活一遍。

改法（三层，Hive 是权威）：

1. **Hive（`optionsBox`）记正式标记** `gradePushIntroShown` —— 和
   `pushOnGradeChange` 同一个盒子，覆盖安装、清缓存都带不走；
2. 文件 / 密钥库降级成"多一道保险"：任意一处说过了就不发，并且**顺手把 Hive 补上**；
3. 换成独立的**低优先级通道** `top.celechron.celechron.tips`（Elychron 提示）——
   它只是告知，不该像成绩变动那样用 `Importance.max` 顶一个横幅出来。

判断本身抽成纯函数 `shouldShowGradePushIntro`，配 5 条单测
（`test/notification_dedup_test.dart`）。

顺带：`NotificationDedup` 的落盘目录从 `Directory.systemTemp` 换成
`getApplicationSupportDirectory()`（手机上是 files 目录），拿不到插件时才退回临时目录 ——
作业截止提醒、成绩变动这两处的去重窗口也跟着一起稳了。
