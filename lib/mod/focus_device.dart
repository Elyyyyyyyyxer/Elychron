import 'dart:convert';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:get/get.dart';

/// ===== 专注记录：来自哪台设备（v1.5.0）=====
///
/// 用户需求：「专注功能同步比较困难，不如在各个设备同步时加上设备名（电脑、安卓）
/// 之类的标注然后直接同步。顺便添加一个分类『按设备』。」
///
/// ⚠️ 关键约束（用户提醒的）：**绝不能动 Hive 的字段结构**。
/// 上次给 FocusSession 加字段时忘了同步 adapter 的字段数，直接搞崩了线上数据。
/// 所以这里一个 Hive 字段都不加：uid → 设备名 的映射、以及"被删掉的专注记录 uid"，
/// 都放在 optionsBox 里（本来就是给"魔改新增的设置"用的地方，见 database_mod.dart）。
///
/// 这样有两个好处：
/// - 老数据零风险（不动存量 Hive 记录的读法）；
/// - 这两个映射跟着 DataBundle 走 JSON 契约同步，跨版本也稳（JSON 里未知键会被忽略）。
class FocusDevice {
  FocusDevice._();

  /// 本机在这份数据里显示成什么
  ///
  /// 用大白话（电脑 / 安卓 / 苹果）而不是型号：用户看统计时要的是
  /// "这条是在哪台设备上专注的"，不是设备指纹。
  static String get current {
    if (PlatformFeatures.isDesktop) return '电脑';
    if (PlatformFeatures.isAndroid) return '安卓';
    return '设备';
  }

  static const String _kLabelsKey = 'focusDeviceLabels';
  static const String _kDeletedKey = 'focusDeletedUids';

  static DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  /// uid → 设备名
  static Map<String, String> labels() {
    final result = <String, String>{};
    try {
      final raw = _db?.optionsBox.get(_kLabelsKey);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            result[key.toString()] = value.toString();
          });
        }
      }
    } catch (_) {
      // 读不出来就当没有标注（显示会退回本机名）
    }
    return result;
  }

  static Future<void> _saveLabels(Map<String, String> labels) async {
    try {
      await _db?.optionsBox.put(_kLabelsKey, jsonEncode(labels));
    } catch (_) {}
  }

  /// 这条记录是哪台设备的（没标注过就返回 null）
  static String? labelOf(String uid) => labels()[uid];

  /// 记一条：本机刚产生的专注记录属于本机
  static Future<void> remember(String uid) async {
    if (uid.isEmpty) return;
    final all = labels();
    if (all[uid] == current) return;
    all[uid] = current;
    await _saveLabels(all);
  }

  /// 合并对方那份标注（同 uid 保留已有的，不覆盖 —— 记录属于产生它的那台设备）
  static Future<void> adopt(Map<String, String> incoming) async {
    if (incoming.isEmpty) return;
    final all = labels();
    var changed = false;
    incoming.forEach((uid, label) {
      if (uid.isEmpty || label.isEmpty) return;
      if (all.containsKey(uid)) return;
      all[uid] = label;
      changed = true;
    });
    if (changed) await _saveLabels(all);
  }

  /// 本机删掉过的专注记录 uid（同步时不再被对方带回来）
  ///
  /// 起因：专注记录的删除原来不参与同步（data_sync.dart 里记着这个已知局限），
  /// 于是"在一端删掉的记录会被另一端同步回来"。用户这次提设备标注时顺带要求
  /// "直接同步就好"，那就把删除也一起同步掉 —— 用一个 uid 集合，
  /// 同样不动 Hive 结构。
  static Set<String> deletedUids() {
    try {
      final raw = _db?.optionsBox.get(_kDeletedKey);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((item) => item.toString()).toSet();
        }
      }
    } catch (_) {}
    return <String>{};
  }

  static Future<void> rememberDeleted(String uid) async {
    if (uid.isEmpty) return;
    final all = deletedUids()..add(uid);
    try {
      await _db?.optionsBox.put(_kDeletedKey, jsonEncode(all.toList()));
    } catch (_) {}
  }

  static Future<void> adoptDeleted(Iterable<String> incoming) async {
    final all = deletedUids();
    final before = all.length;
    all.addAll(incoming.where((uid) => uid.isNotEmpty));
    if (all.length == before) return;
    try {
      await _db?.optionsBox.put(_kDeletedKey, jsonEncode(all.toList()));
    } catch (_) {}
  }
}
