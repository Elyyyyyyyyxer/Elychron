import 'package:celechron/utils/platform_features.dart';
import 'package:flutter_test/flutter_test.dart';

/// 平台能力表（v1.5.0 桌面端）。
///
/// 这张表是"安卓专属功能在桌面上怎么办"的唯一判据：调用方全靠它来决定
/// 是走另一套实现、还是安静跳过。写错一格的后果是桌面端启动/进页面直接抛
/// MissingPluginException，所以这里把口径钉住。
///
/// 测试跑在**桌面**（flutter test 用的是宿主平台 = Windows），
/// 所以这份断言实际验的就是"桌面端该拿到什么"。
void main() {
  test('跑测试的这台机器是桌面端', () {
    expect(PlatformFeatures.isDesktop, isTrue);
    expect(PlatformFeatures.isMobile, isFalse);
    expect(PlatformFeatures.isAndroid, isFalse);
  });

  test('安卓专属的三样在桌面端都是 false（AppWidget / 系统 DND / 全屏通知）', () {
    expect(PlatformFeatures.hasHomeWidgets, isFalse);
    expect(PlatformFeatures.hasDoNotDisturb, isFalse);
    expect(PlatformFeatures.hasFullScreenIntent, isFalse);
    expect(PlatformFeatures.hasAlarmChannel, isFalse);
  });

  test('手机专属的入口在桌面端关闭（分享 / WorkManager / 系统通知 / device_calendar）', () {
    expect(PlatformFeatures.canReceiveShares, isFalse);
    expect(PlatformFeatures.hasBackgroundRefresh, isFalse);
    expect(PlatformFeatures.hasSystemNotifications, isFalse);
    expect(PlatformFeatures.usesDeviceCalendarPlugin, isFalse);
    expect(PlatformFeatures.hasDeviceInfoPlugin, isFalse);
  });

  test('"换一套做法"的能力在桌面端仍然算有', () {
    // 系统日历：桌面上改走 .ics 导出，所以 hasSystemCalendar 是 true，
    // 但"用不用 device_calendar 插件"是 false —— 这两个必须分开，
    // 否则要么桌面端白调插件、要么界面把导出入口也藏了。
    expect(PlatformFeatures.hasSystemCalendar, isFalse,
        reason: '桌面端不写系统日历，只导出 .ics');
    expect(PlatformFeatures.hasAlarmSound, isTrue,
        reason: '桌面端用系统提示音兜底，仍然"有声音"');
  });

  test('unsupportedReason 在桌面端给出一句话，在手机上不给', () {
    expect(PlatformFeatures.unsupportedReason('桌面小组件'), contains('桌面端暂未实现'));
    // 手机上不显示这句话（这里跑在桌面，只能验桌面分支）
  });
}
