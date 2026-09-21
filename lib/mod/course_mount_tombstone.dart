import 'dart:convert';

import 'package:celechron/database/database_helper.dart';
import 'package:get/get.dart';

/// ===== 课程挂载的删除墓碑（v1.5.0）=====
///
/// 用户要求：「删除的墓碑机制补全」。
///
/// 现状：待办早就按 uid 记墓碑（TaskTombstone）、专注记录上一轮也补了 uid 集合，
/// 只剩**课程挂载的资料与评论**没有 —— 而它们的合并口径是"取并集"，于是
/// 在一端删掉的资料/评论会被另一端原样带回来（这就是"补全"要解决的最后一处）。
///
/// 做法与专注记录完全一致，**不动任何 Hive 结构**：把"删掉的键"存进 optionsBox，
/// 随 DataBundle 走 JSON 契约同步。键的构造：
/// - 资料：「courseId|a|path」（同一个文件两台都加过时 path 是稳定的）
/// - 评论：「courseId|c|内容@时间」（评论没有 uid，用内容+时间当身份）
///
/// ⚠️ 局限（写清楚免得以后踩）：删完之后**又用同样的路径/内容加回来**，
/// 会因为键相同而被当成"已删除"过滤掉。这个口径与专注记录那边一致，属于可接受的取舍。
class CourseMountTombstone {
  CourseMountTombstone._();

  static const String _key = 'courseMountDeleted';

  static DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  static String attachmentKey(String courseId, String path) =>
      courseId + '|a|' + path;

  static String commentKey(String courseId, String content, int time) =>
      courseId + '|c|' + content + '@' + time.toString();

  /// 已删除的键集合
  static Set<String> all() {
    try {
      final raw = _db?.optionsBox.get(_key);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((item) => item.toString()).toSet();
        }
      }
    } catch (_) {}
    return <String>{};
  }

  static Future<void> _save(Set<String> keys) async {
    try {
      await _db?.optionsBox.put(_key, jsonEncode(keys.toList()));
    } catch (_) {}
  }

  static Future<void> remember(String tombstoneKey) async {
    if (tombstoneKey.isEmpty) return;
    final keys = all()..add(tombstoneKey);
    await _save(keys);
  }

  /// 收下对方那份（并集，不覆盖已有的）
  static Future<void> adopt(Iterable<String> incoming) async {
    final keys = all();
    final before = keys.length;
    keys.addAll(incoming.where((item) => item.isNotEmpty));
    if (keys.length == before) return;
    await _save(keys);
  }
}
