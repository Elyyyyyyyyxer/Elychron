import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/tombstone.dart';
import 'package:hive/hive.dart';

/// ============ 魔改在数据库层新增的读写（墓碑 / 标签库 / 配色 / 提醒方式）============
///
/// 上游的 `lib/database/database_helper.dart` 也被持续维护，所以这些成员不再写在
/// 那个类里，而是用 extension 挂在它上面——`optionsBox` / `tombstoneBox` 都是
/// public 字段，extension 能直接访问。
/// 上游文件里只留 4 行 adapter 注册与 1 行开箱。
/// 删除墓碑的 Hive key
const String kTombstones = 'tombstones';
const String kReminderModeKey = 'reminderMode';
const String kAlarmThemeKey = 'alarmTheme';
const String kTagLibraryKey = 'tagLibrary';
const String kTagColorsKey = 'tagColors';

/// 专注时自动免打扰：开关本身（默认开）
const String kFocusDndKey = 'focusDndEnabled';

/// 开启免打扰**之前**的系统档位。
///
/// 落盘是为了防「App 被杀导致手机永久静音」：下次启动时如果发现这个键还在，
/// 说明我们改过却没来得及还原，就立刻还原（见 `DoNotDisturb.restoreIfStale`）。
const String kDndSavedFilterKey = 'dndSavedFilter';

extension DatabaseModExt on DatabaseHelper {
  // 专注时自动免打扰

  bool getFocusDndEnabled() {
    final value = optionsBox.get(kFocusDndKey);
    if (value is bool) return value;
    return true; // 默认开：这正是这个功能的意义
  }

  Future<void> setFocusDndEnabled(bool enabled) async {
    await optionsBox.put(kFocusDndKey, enabled);
  }

  int? getDndSavedFilter() {
    final value = optionsBox.get(kDndSavedFilterKey);
    return value is int ? value : null;
  }

  Future<void> setDndSavedFilter(int filter) async {
    await optionsBox.put(kDndSavedFilterKey, filter);
  }

  Future<void> clearDndSavedFilter() async {
    await optionsBox.delete(kDndSavedFilterKey);
  }

  // 提醒方式：0 = 通知（横幅+响铃），1 = 闹钟模式

  int getReminderMode() {
    final value = optionsBox.get(kReminderModeKey);
    if (value is int) return value;
    return 0;
  }

  Future<void> setReminderMode(int mode) async {
    await optionsBox.put(kReminderModeKey, mode);
  }

  // 闹钟配色

  String getAlarmTheme() {
    final value = optionsBox.get(kAlarmThemeKey);
    if (value is String && value.isNotEmpty) return value;
    return 'tianyi';
  }

  Future<void> setAlarmTheme(String id) async {
    await optionsBox.put(kAlarmThemeKey, id);
  }

  // 标签库：用户用过的标签，下次可以一键复用

  List<String> getTagLibrary() {
    if (optionsBox.get(kTagLibraryKey) == null) {
      optionsBox.put(kTagLibraryKey, <String>[]);
    }
    return List<String>.from(optionsBox.get(kTagLibraryKey));
  }

  /// 写入标签库；默认拒绝空列表（防止意外清空），只有用户在标签管理里
  /// 主动删光时才传 allowEmpty: true。
  Future<void> setTagLibrary(List<String> tags,
      {bool allowEmpty = false}) async {
    if (tags.isEmpty && !allowEmpty) return;
    await optionsBox.put(kTagLibraryKey, tags);
  }

  // 标签颜色：标签名 -> 颜色值（ARGB int）

  Map<String, int> getTagColors() {
    final raw = optionsBox.get(kTagColorsKey);
    if (raw == null) return <String, int>{};
    return Map<String, int>.from(raw as Map);
  }

  Future<void> setTagColors(Map<String, int> colors) async {
    await optionsBox.put(kTagColorsKey, colors);
  }

  /// 标签颜色（没设过返回 null，由界面决定默认色）
  int? getTagColor(String tag) => getTagColors()[tag];

  Future<void> setTagColor(String tag, int? color) async {
    final colors = getTagColors();
    if (color == null) {
      colors.remove(tag);
    } else {
      colors[tag] = color;
    }
    await setTagColors(colors);
  }

  // 删除墓碑
  List<TaskTombstone> getTombstones() {
    final raw = tombstoneBox.get(kTombstones);
    if (raw is! List) return <TaskTombstone>[];
    final result = <TaskTombstone>[];
    for (final item in raw) {
      if (item is Map) {
        final tombstone =
            TaskTombstone.fromJson(Map<String, dynamic>.from(item));
        if (tombstone != null) result.add(tombstone);
      }
    }
    return result;
  }

  Future<void> setTombstones(List<TaskTombstone> tombstones) async {
    await tombstoneBox.put(
        kTombstones, tombstones.map((t) => t.toJson()).toList());
  }

  /// 记录一批待办被删除（同 uid 只保留最新时间）
  Future<void> addTombstones(Iterable<String> uids, {DateTime? at}) async {
    if (uids.isEmpty) return;
    final now = at ?? DateTime.now();
    final map = <String, TaskTombstone>{
      for (final tombstone in getTombstones()) tombstone.uid: tombstone,
    };
    for (final uid in uids) {
      map[uid] = TaskTombstone(uid: uid, deletedAt: now);
    }
    await setTombstones(map.values.toList());
  }

  // Scholar
}
