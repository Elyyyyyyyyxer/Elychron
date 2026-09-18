import 'package:celechron/database/database_helper.dart';
import 'package:get/get.dart';

/// ===== 桌面提醒音的选择（v1.5.0）=====
///
/// 用户要求把一个"爱莉原声"当小彩蛋：长按「测试提醒」切换过去，再长按切回来。
/// 所以只存一个偏好，不作设置项暴露（彩蛋嘛）。
///
/// ⚠️ 原声是受版权保护的音频，**不进仓库**（.gitignore 里排掉了 assets/sounds/ely_hi.*）。
/// 用法：把音频放到 assets/sounds/ely_hi.mp3（tools 里有裁剪脚本），重新构建即可。
enum DesktopAlertSound {
  /// 内置的空灵高音钢琴提示音（默认）
  chime,

  /// 爱莉原声（彩蛋）
  voice,
}

class DesktopAlertSoundStore {
  DesktopAlertSoundStore._();

  static const String _key = 'desktopAlertSound';

  static DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  /// 当前选择（读不出来就用默认的内置音）
  static DesktopAlertSound get current {
    try {
      final raw = _db?.optionsBox.get(_key);
      if (raw == 'voice') return DesktopAlertSound.voice;
    } catch (_) {
      // 读失败按默认处理
    }
    return DesktopAlertSound.chime;
  }

  static Future<void> set(DesktopAlertSound sound) async {
    try {
      await _db?.optionsBox.put(_key, sound.name);
    } catch (_) {
      // 落盘失败只影响下次启动，不影响本次发声
    }
  }

  /// 切到另一个（长按彩蛋用），返回切换后的值
  static Future<DesktopAlertSound> toggle() async {
    final next = current == DesktopAlertSound.chime
        ? DesktopAlertSound.voice
        : DesktopAlertSound.chime;
    await set(next);
    return next;
  }

  static String describe(DesktopAlertSound sound) =>
      sound == DesktopAlertSound.voice ? '爱莉原声（彩蛋）' : '内置钢琴音';
}
