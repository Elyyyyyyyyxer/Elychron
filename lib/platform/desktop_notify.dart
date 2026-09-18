import 'package:audioplayers/audioplayers.dart';
import 'package:celechron/platform/desktop_alert_sound.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:local_notifier/local_notifier.dart';

/// ===== 桌面端通知（v1.5.0）=====
///
/// 用户拍板：「桌面端换用 windows 支持的」「闹钟就模仿钉钉的 DING 功能，
/// 响一下在桌面右下角有一个弹窗」。
///
/// 实现：**local_notifier**（Windows 原生 Toast，默认就在右下角）+ **audioplayers**
/// 放一段自己合成的 ding（assets/sounds/ding.wav，无版权问题），响一下就够，不循环。
///
/// ⚠️ 2026-09-18 踩过的两个坑（都写进日志，方便下次一眼定位）：
/// 1. 插件没注册时（windows/flutter/generated_plugins.cmake 里没有 local_notifier），
///    这里会抛 MissingPluginException，**用户看到的就是"没弹窗也没声音"**；
/// 2. Windows 的 Toast 需要一条带 AUMID 的开始菜单快捷方式，
///    所以 setup 默认用 ShortcutPolicy.requireCreate；万一创建失败，
///    退回 ignore 再试一次（宁可弹得不那么"正规"，也别什么都不弹）。
class DesktopNotify {
  DesktopNotify._();

  static bool _inited = false;
  static bool _ready = false;
  static AudioPlayer? _player;

  static void _log(String message) {
    try {
      DiagnosticLogService.instance.record(
        module: '桌面通知',
        operation: 'ding',
        message: message,
      );
    } catch (_) {}
  }

  /// 首次使用前初始化（幂等）。返回是否可用。
  static Future<bool> ensureReady() async {
    if (!PlatformFeatures.isDesktop) return false;
    if (_inited) return _ready;
    _inited = true;
    try {
      await localNotifier.setup(
        appName: 'Elychron',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _ready = true;
      _log('初始化成功（已创建开始菜单快捷方式）');
      return true;
    } catch (error) {
      _log('初始化失败（requireCreate）：' + error.toString());
    }
    try {
      await localNotifier.setup(
        appName: 'Elychron',
        shortcutPolicy: ShortcutPolicy.ignore,
      );
      _ready = true;
      _log('初始化成功（ignore 模式，不建快捷方式）');
      return true;
    } catch (error) {
      _log('初始化彻底失败：' + error.toString());
      _ready = false;
      return false;
    }
  }

  /// DING：响一下 + 右下角弹窗
  static Future<void> ding({
    required String title,
    String? body,
    void Function()? onTap,
  }) async {
    if (!PlatformFeatures.isDesktop) return;
    _log('触发：' + title);
    final ready = await ensureReady();
    final soundOk = await _playDing();
    if (!ready) {
      _log('弹窗跳过（通知未初始化成功）；声音=' + (soundOk ? '已响' : '失败'));
      return;
    }
    try {
      final notification = LocalNotification(title: title, body: body ?? '');
      if (onTap != null) notification.onClick = onTap;
      await notification.show();
      _log('弹窗已发出；声音=' + (soundOk ? '已响' : '失败'));
    } catch (error) {
      _log('弹窗失败：' + error.toString());
    }
  }

  /// 优先播放"人声"（用户把音频丢进 assets/sounds/ 就会自动用上），
  /// 找不到再退回自合成的 ding。
  ///
  /// 用户希望能用爱莉的那句"嗨~"原声 —— 但原声是受版权保护的音频，
  /// 我不能凭空生成或内置，所以做成"你把文件放进来就行"：
  /// 把音频放到 assets/sounds/ 下并命名为下列任一名字（见 [_voiceCandidates]），
  /// 重新构建后就会优先播它。pubspec 里已经声明了整个 assets/sounds/ 目录，
  /// 放文件即可，不用改代码。
  static const List<String> _voiceCandidates = <String>[
    'sounds/ely_hi.mp3',
    'sounds/ely_hi.m4a',
    'sounds/ely_hi.wav',
    'sounds/voice.mp3',
    'sounds/voice.wav',
  ];

  /// 播放提示音，返回是否成功。
  ///
  /// 音源由 [DesktopAlertSoundStore] 决定（长按「测试提醒」可切换）：
  /// - [DesktopAlertSound.chime] → 内置的空灵高音钢琴音（assets/sounds/ding.wav）
  /// - [DesktopAlertSound.voice] → 爱莉原声（assets/sounds/ely_hi.*，**不进仓库**）
  /// 选了原声但文件不存在时会安静退回内置音，并写进诊断日志。
  static Future<bool> _playDing() async {
    // 默认什么都不放：Windows 的 Toast 自带系统提示音，够用且最自然
    // （用户 2026-09-19 拍板取消自制的 DING 音）。
    // 只有切到"爱莉原声"彩蛋时才自己放音频。
    if (DesktopAlertSoundStore.current != DesktopAlertSound.voice) {
      return true;
    }
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      for (final asset in _voiceCandidates) {
        try {
          await _player!.play(AssetSource(asset));
          _log('播放原声：' + asset);
          return true;
        } catch (_) {
          // 这个候选不存在/放不了，试下一个
        }
      }
      _log('选了原声但没找到音频文件（assets/sounds/ely_hi.*）');
      return false;
    } catch (error) {
      _log('原声播放失败：' + error.toString());
      return false;
    }
  }
}
