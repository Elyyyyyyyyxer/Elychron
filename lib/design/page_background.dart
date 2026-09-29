import 'package:flutter/cupertino.dart';

/// ===== 页面底色（全平台统一）=====
///
/// 历史：手机端原来用**分组灰**（`systemGroupedBackground`）——
/// `CupertinoListSection` 会往每个分组下面铺一块同样偏灰的底，
/// 两者同色才不会有"白底衬灰块"的观感（这个坑教程页踩过）。
/// 桌面端在 v1.5.0 改成了系统白（用户反馈"日程页是白的、专注页和设置页是灰的，很割裂"）。
///
/// 但手机端这么做还是不对：走这个函数的只有"设置"这一条线
/// （设置页 + 它延伸出去的同步 / AI / 教程 / 测试日志等子页面），
/// 而日程、待办、专注那几个主页面是**白底卡片**。
/// 结果同一台手机上白一半灰一半。
/// 用户原话（2026-09-29）：「设置界面（好像设置页面延伸的一些子页面也有）的
/// 背景底色好像还是会有一层灰色，跟其他页面不搭配，请删掉」。
///
/// 所以现在**全平台统一**用 `systemBackground`（浅色=白，深色=黑）。
/// 分组列表的底色也从这个函数取，跟着一起变，不会出现"白底衬灰块"。
Color pageBackground(BuildContext context) =>
    CupertinoDynamicColor.resolve(CupertinoColors.systemBackground, context);
