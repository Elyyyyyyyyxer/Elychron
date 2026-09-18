import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/services.dart';

/// 闹钟模式的铃声：调用原生播放系统默认闹钟铃声（循环），退出应用/划掉时停止。
class AlarmPlayer {
  AlarmPlayer._();

  static const MethodChannel _channel = MethodChannel('celechron/alarm');
  static bool _playing = false;

  static Future<void> start() async {
    if (_playing) return;
    _playing = true;
    // 桌面端没有那条原生音频通道（也就没有"循环响铃"），用系统提示音兜底：
    // 响一声 + 闹钟界面照常弹出，先保证"叫得醒"，循环响铃等拍板再补
    // （要么引第三方音频包，要么写 Windows 原生播放）。
    if (PlatformFeatures.isDesktop) {
      await SystemSound.play(SystemSoundType.alert);
      return;
    }
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {
      _playing = false;
    }
  }

  /// Android 14+ 是否已授予全屏通知权限（没有的话闹钟只弹通知、不弹全屏）
  static Future<bool> canUseFullScreenIntent() async {
    if (!PlatformFeatures.hasFullScreenIntent) return true;
    try {
      final value = await _channel.invokeMethod<bool>('canUseFullScreenIntent');
      return value ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 跳到系统的全屏通知授权页
  static Future<void> openFullScreenIntentSettings() async {
    if (!PlatformFeatures.hasFullScreenIntent) return;
    try {
      await _channel.invokeMethod<void>('openFullScreenIntentSettings');
    } catch (_) {}
  }

  /// 是否已加入电池优化白名单（国产 ROM 不加入的话后台闹钟容易被掐掉）
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final value =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openBatterySettings() async {
    if (!PlatformFeatures.hasFullScreenIntent) return;
    try {
      await _channel.invokeMethod<void>('openBatterySettings');
    } catch (_) {}
  }

  /// 闹钟渠道当前重要度：5=MAX 正常；被系统降级会变成 3（就不响也不弹全屏了）
  static Future<int> alarmChannelImportance() async {
    if (!PlatformFeatures.hasAlarmChannel) return -1;
    try {
      final value =
          await _channel.invokeMethod<int>('getAlarmChannelImportance');
      return value ?? -1;
    } catch (_) {
      return -1;
    }
  }

  /// 跳到系统里本应用待办闹钟渠道的设置页（用户可手动调回高重要度）
  static Future<void> openAlarmChannelSettings() async {
    if (!PlatformFeatures.hasAlarmChannel) return;
    try {
      await _channel.invokeMethod<void>('openAlarmChannelSettings');
    } catch (_) {}
  }

  /// 跳到本应用的系统通知设置页（重要度被压时，用户需要在这里调回来）
  static Future<void> openAppNotificationSettings() async {
    if (!PlatformFeatures.hasAlarmChannel) return;
    try {
      await _channel.invokeMethod<void>('openAppNotificationSettings');
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    if (PlatformFeatures.isDesktop) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
