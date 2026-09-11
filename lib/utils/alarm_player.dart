import 'package:flutter/services.dart';

/// 闹钟模式的铃声：调用原生播放系统默认闹钟铃声（循环），退出应用/划掉时停止。
class AlarmPlayer {
  AlarmPlayer._();

  static const MethodChannel _channel = MethodChannel('celechron/alarm');
  static bool _playing = false;

  static Future<void> start() async {
    if (_playing) return;
    _playing = true;
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {
      _playing = false;
    }
  }

  /// Android 14+ 是否已授予「全屏通知」权限（没有的话闹钟只弹通知、不弹全屏）
  static Future<bool> canUseFullScreenIntent() async {
    try {
      final value = await _channel.invokeMethod<bool>('canUseFullScreenIntent');
      return value ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 跳到系统的「全屏通知」授权页
  static Future<void> openFullScreenIntentSettings() async {
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
    try {
      await _channel.invokeMethod<void>('openBatterySettings');
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
