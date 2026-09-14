import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// 专注时自动免打扰（DND）。
///
/// ## 为什么要记录「改之前是什么档位」
///
/// 免打扰是**系统级**状态：如果只是在开始时切成静音、结束时还原成固定值，
/// 那原本就开着免打扰（或设成「仅允许闹钟」）的用户会被我们改掉。
/// 更麻烦的是**中途被杀**：App 被系统清掉时结束回调不会执行，
/// 用户的手机就永久静音了 —— 所以当前档位要落盘，
/// 下次启动时发现"我们改过但没还原"就立刻还原（见 [restoreIfStale]）。
///
/// ## 权限
///
/// 「勿扰访问权限」是特殊权限，装机时不会自动授予，得用户自己去系统设置里开。
/// 没授权时所有写操作返回 false，由界面引导用户去授权（不静默失败）。
class DoNotDisturb {
  DoNotDisturb._();

  static const MethodChannel _channel = MethodChannel('celechron/dnd');

  /// 安卓的免打扰档位常量（与 NotificationManager 一致）
  static const int filterAll = 1; // 全部允许
  static const int filterPriority = 2; // 仅允许优先
  static const int filterNone = 4; // 完全静音
  static const int filterAlarms = 5; // 仅允许闹钟

  /// 中文化档位（用于提示）
  static String filterName(int filter) => switch (filter) {
        filterAll => '全部允许',
        filterPriority => '仅优先',
        filterNone => '完全静音',
        filterAlarms => '仅闹钟',
        _ => '未知档位',
      };

  static DatabaseHelper? get _db {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return null;
    return Get.find<DatabaseHelper>(tag: 'db');
  }

  /// 有没有拿到勿扰访问权限
  static Future<bool> isGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isGranted') ?? false;
    } on Object {
      return false;
    }
  }

  /// 当前档位（拿不到时按「全部允许」处理，尽量保守）
  static Future<int> currentFilter() async {
    try {
      return await _channel.invokeMethod<int>('currentFilter') ?? filterAll;
    } on Object {
      return filterAll;
    }
  }

  /// 跳到系统授权页
  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on Object {
      // 跳不过去就算了，界面已经写明路径
    }
  }

  static Future<bool> _setFilter(int filter) async {
    try {
      return await _channel.invokeMethod<bool>('setFilter', {'filter': filter})
          ?? false;
    } on Object {
      return false;
    }
  }

  /// 开始专注时调用：把当前档位记下来，再切成完全静音。
  ///
  /// 返回 false 表示没生效（多半是没授权），调用点据此决定要不要提示。
  static Future<bool> enableForFocus() async {
    final db = _db;
    if (db == null) return false;
    final before = await currentFilter();
    if (before == filterNone) {
      // 本来就已经静音了：什么都不用改，也不必记（结束时不该动用户自己的设置）
      db.clearDndSavedFilter();
      return true;
    }
    final ok = await _setFilter(filterNone);
    if (ok) {
      db.setDndSavedFilter(before);
    }
    return ok;
  }

  /// 结束专注时调用：还原成开始之前那个档位
  static Future<void> restore() async {
    final db = _db;
    if (db == null) return;
    final saved = db.getDndSavedFilter();
    if (saved == null) return; // 我们没改过，别乱动
    await _setFilter(saved);
    db.clearDndSavedFilter();
  }

  /// 启动时调用：如果上次改过却没还原（App 被系统杀掉了），现在就还原。
  ///
  /// 只处理「我们确实留了记录」的情况 —— 用户自己开的免打扰不动。
  static Future<void> restoreIfStale() async {
    final db = _db;
    if (db == null) return;
    final saved = db.getDndSavedFilter();
    if (saved == null) return;
    final restored = await _setFilter(saved);
    if (restored) {
      db.clearDndSavedFilter();
    }
  }

  /// 「专注时自动免打扰」这个开关本身是否打开
  static bool autoEnabled() => _db?.getFocusDndEnabled() ?? true;
}
