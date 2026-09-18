import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

/// ===== 平台能力表 =====
///
/// 这个基座最初是**安卓**的：闹钟靠原生全屏通知、免打扰靠系统 DND、
/// 桌面小组件靠 AppWidget、分享靠 Intent、系统日历靠 device_calendar、
/// 后台刷新靠 WorkManager。这些在桌面端（v1.5.0 起正式支持）**要么换一套做法、
/// 要么暂时没有**，所以统一在这里列一张表：
/// 调用方一律问这张表，不要各写各的 «Platform.isXXX» ——
/// 一处写错就是桌面端启动崩（MissingPluginException 或根本没有那个插件）。
///
/// 口径：
/// - **能用另一套实现的**返回 true，由各自的实现文件按平台分叉
///   （例：系统日历在手机上是 device_calendar，桌面上走 .ics 导出）；
/// - **桌面端暂时没有的**返回 false，调用方安静跳过（不报错、不弹错），
///   界面上写明"桌面端暂不支持"—— 先搭壳子，等拍板再补。
final class PlatformFeatures {
  static bool get isMobile {
    return !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  }

  static bool get isDesktop {
    return !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  }

  /// 是不是安卓（有些能力是安卓独有的：AppWidget、全屏通知、系统 DND）
  static bool get isAndroid {
    return !kIsWeb && Platform.isAndroid;
  }

  static bool get hasBackgroundRefresh {
    return isMobile;
  }

  static bool get hasWidgetSupport {
    return isMobile;
  }

  // ===== 2026-09-18 桌面端新增：逐项说清"桌面怎么办" =====

  /// 桌面小组件（最近待办 / 校园卡）：安卓的 AppWidget，桌面端没有对应物
  static bool get hasHomeWidgets => isAndroid;

  /// 系统级免打扰：安卓有这套开关；Windows 的"专注助手"是另一回事，先不做
  static bool get hasDoNotDisturb => isAndroid;

  /// 闹钟铃声：手机走原生音频通道（能循环响），桌面端用系统提示音兜底
  static bool get hasAlarmSound => isMobile || isDesktop;

  /// 闹钟渠道 / 全屏通知（安卓 14+ 那套）：只有安卓有
  static bool get hasAlarmChannel => isAndroid;
  static bool get hasFullScreenIntent => isAndroid;

  /// 接收系统分享（Intent）：桌面端没有这个入口
  static bool get canReceiveShares => isMobile;

  /// 写系统日历：手机上是 device_calendar 插件；桌面上改用 .ics 导出
  static bool get hasSystemCalendar => isMobile;

  /// 系统日历是不是就是 device_calendar 那一套（桌面端不碰这个插件）
  static bool get usesDeviceCalendarPlugin => isMobile;

  /// 系统通知：手机上有；桌面端当前依赖的插件没有 Windows 实现，
  /// 先留壳子（应用内提醒照常，只是不出系统通知）
  static bool get hasSystemNotifications => isMobile;

  /// 读取设备型号（反馈信息里那一行）：桌面端插件没实现，用系统名兜底
  static bool get hasDeviceInfoPlugin => isMobile;

  /// 给界面用的一句话：这个能力在桌面端是什么状态
  static String unsupportedReason(String feature) =>
      isDesktop ? feature + ' 在桌面端暂未实现（v1.5.0 先保留入口）' : '';
}
