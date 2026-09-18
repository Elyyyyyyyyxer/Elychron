import 'package:audioplayers/audioplayers.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:local_notifier/local_notifier.dart';

/// ===== 桌面端通知（v1.5.0）=====
///
/// 用户拍板：「桌面端换用 windows 支持的」「闹钟就模仿钉钉的 DING 功能，
/// 响一下在桌面右下角有一个弹窗」。
///
/// 所以桌面端不用手机那套（flutter_local_notifications 没有 Windows 实现），
/// 改成 **local_notifier**：Windows 原生 Toast，默认就在右下角。
/// 声音用 audioplayers 放我们自己合成的一段 ding（assets/sounds/ding.wav，
/// 没有版权问题），"响一下"就够了，不循环。
///
/// 手机端一行都不走这里（[PlatformFeatures.isDesktop] 为 false 时全部直接返回）。
class DesktopNotify {
  DesktopNotify._();

  static bool _inited = false;
  static AudioPlayer? _player;

  /// 首次使用前初始化（幂等）
  static Future<void> ensureReady() async {
    if (!PlatformFeatures.isDesktop || _inited) return;
    _inited = true;
    try {
      await localNotifier.setup(appName: 'Elychron');
    } catch (_) {
      // 托盘/通知中心不可用时不该影响主流程
    }
  }

  /// DING：响一下 + 右下角弹窗
  ///
  /// [onTap] 一般用来把窗口拉到前台（用户看到弹窗想直接处理）。
  static Future<void> ding({
    required String title,
    String? body,
    void Function()? onTap,
  }) async {
    if (!PlatformFeatures.isDesktop) return;
    await ensureReady();
    await _playDing();
    try {
      final notification = LocalNotification(
        title: title,
        body: body ?? '',
      );
      if (onTap != null) {
        notification.onClick = onTap;
      }
      await notification.show();
    } catch (_) {
      // 弹窗失败也不能把闹钟流程搞崩（声音已经响过了）
    }
  }

  static Future<void> _playDing() async {
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.play(AssetSource('sounds/ding.wav'));
    } catch (_) {
      // 没有音频设备（远程桌面等）时安静跳过
    }
  }
}
