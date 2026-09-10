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

  static Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
