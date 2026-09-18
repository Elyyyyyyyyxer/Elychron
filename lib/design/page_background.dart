import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/cupertino.dart';

/// ===== 页面底色（v1.5.0 桌面端）=====
///
/// 手机端的页面底色是**分组灰**（`systemGroupedBackground`）：
/// `CupertinoListSection` 会往每个分组下面铺一块同样偏灰的底，
/// 两者同色才不会有"白底衬灰块"的观感（这个坑教程页踩过）。
///
/// 但桌面端不一样：那里没有手机那种"整页分组列表"的观感，
/// 用户看到的是"日程页是白的、专注页和设置页是灰的"，很割裂
/// （2026-09-19 反馈："专注和设置页面还是有灰底，我强烈怀疑还有很多页面也没有改"）。
///
/// 所以桌面端统一用系统白，手机端维持分组灰。所有页面底色都走这一个函数，
/// 以后要调只改这里。
Color pageBackground(BuildContext context) => CupertinoDynamicColor.resolve(
      PlatformFeatures.isDesktop
          ? CupertinoColors.systemBackground
          : CupertinoColors.systemGroupedBackground,
      context,
    );
