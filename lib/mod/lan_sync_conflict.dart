import 'dart:convert';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/task.dart';
import 'package:get/get.dart';

/// ===== 局域网同步：字段级冲突（v1.5.0）=====
///
/// 用户要求：「两边都改过的时候展示冲突的字段，允许在其中做选择」。
///
/// 背景：现在的合并口径是**整条待办按 updatedAt 晚者胜**（见 DataMerge.merge）——
/// 于是"手机改标题、电脑改截止时间"这种场景，晚改的那一条会把整条覆盖掉，
/// 另一边改的字段就**静默丢了**（只在结果里记一个 conflictUids 的数字）。
///
/// 这里把"到底哪些字段不一致"算出来，连同两边的值一起存下来，
/// 让用户自己挑 —— 挑完写回本机并抬高 updatedAt，下一次同步就按他选的那份传播。
///
/// 只做**待办**的字段级冲突：标签库、专注记录、设置项的冲突概率低、
/// 代价小（见 data_sync.dart 里的注释），不值得为它们做一套选择界面。
class LanSyncConflict {
  /// 冲突的待办 uid
  final String uid;

  /// 标题（用来看是哪一条，展示时用当时的值）
  final String title;

  /// 字段名 → [本机值, 对方值]（都是给人看的字符串）
  final Map<String, List<String>> fields;

  /// 检测时间
  final DateTime detectedAt;

  /// 本机那一版（「用本机」时按字段抄回来用）
  final Map<String, dynamic> localJson;

  /// 对方那一版
  final Map<String, dynamic> remoteJson;

  const LanSyncConflict({
    required this.uid,
    required this.title,
    required this.fields,
    required this.detectedAt,
    this.localJson = const <String, dynamic>{},
    this.remoteJson = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uid': uid,
        'title': title,
        'fields': fields,
        'detectedAt': detectedAt.toIso8601String(),
        'local': localJson,
        'remote': remoteJson,
      };

  static LanSyncConflict? fromJson(Map<String, dynamic> json) {
    final uid = json['uid']?.toString() ?? '';
    if (uid.isEmpty) return null;
    final rawFields = json['fields'];
    final fields = <String, List<String>>{};
    if (rawFields is Map) {
      rawFields.forEach((key, value) {
        if (value is List && value.length >= 2) {
          fields[key.toString()] = <String>[
            value[0]?.toString() ?? '',
            value[1]?.toString() ?? '',
          ];
        }
      });
    }
    Map<String, dynamic> sub(Object? raw) =>
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return LanSyncConflict(
      uid: uid,
      title: json['title']?.toString() ?? '',
      fields: fields,
      localJson: sub(json['local']),
      remoteJson: sub(json['remote']),
      detectedAt: DateTime.tryParse(json['detectedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// 比较两条同名待办，返回**不一致的字段**（纯函数，有单测）
///
/// 返回：字段名 → [本机值, 对方值]。两边一样、或者都算"空"的字段不会出现。
/// 字段名用中文，直接可以显示给用户。
Map<String, List<String>> diffTasks(Task local, Task remote) {
  final diff = <String, List<String>>{};

  void compare(String label, String localValue, String remoteValue) {
    if (localValue == remoteValue) return;
    diff[label] = <String>[localValue, remoteValue];
  }

  String text(String? value) => (value ?? '').trim();
  String two(int value) => value.toString().padLeft(2, '0');
  String time(DateTime? value) {
    if (value == null) return '（无）';
    return value.year.toString() +
        '-' +
        two(value.month) +
        '-' +
        two(value.day) +
        ' ' +
        two(value.hour) +
        ':' +
        two(value.minute);
  }

  String list(List<String> values) => values.isEmpty ? '（无）' : values.join('、');

  compare('标题', text(local.summary), text(remote.summary));
  compare('描述', text(local.description), text(remote.description));
  compare(
      '类型', taskKindName[local.type] ?? '', taskKindName[remote.type] ?? '');
  compare('地点', text(local.location), text(remote.location));
  compare('开始时间', time(local.startTime), time(remote.startTime));
  compare('截止时间', time(local.endTime), time(remote.endTime));
  compare('标签', list(local.tags), list(remote.tags));
  compare('星标', local.starred ? '是' : '否', remote.starred ? '是' : '否');
  compare(
    '优先级',
    local.priority.name,
    remote.priority.name,
  );
  compare(
    '子待办',
    local.subtasks.isEmpty
        ? '（无）'
        : local.subtasks.map((sub) => sub.title).join('、'),
    remote.subtasks.isEmpty
        ? '（无）'
        : remote.subtasks.map((sub) => sub.title).join('、'),
  );
  compare(
    '附件',
    local.attachments.isEmpty
        ? '（无）'
        : local.attachments.map((item) => item.name).join('、'),
    remote.attachments.isEmpty
        ? '（无）'
        : remote.attachments.map((item) => item.name).join('、'),
  );
  compare(
    '评论',
    local.comments.isEmpty
        ? '（无）'
        : local.comments.map((item) => item.content).join('、'),
    remote.comments.isEmpty
        ? '（无）'
        : remote.comments.map((item) => item.content).join('、'),
  );
  compare('提醒', local.reminderEnabled ? '开' : '关',
      remote.reminderEnabled ? '开' : '关');
  compare('提醒时间', time(local.reminderTime), time(remote.reminderTime));

  return diff;
}

/// ===== 冲突的存取（放 optionsBox，重启后还在）=====
class LanSyncConflictStore {
  LanSyncConflictStore._();

  static const String _key = 'lanSyncConflicts';

  static DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  static List<LanSyncConflict> load() {
    try {
      final raw = _db?.optionsBox.get(_key);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((item) =>
                  LanSyncConflict.fromJson(Map<String, dynamic>.from(item)))
              .whereType<LanSyncConflict>()
              .toList();
        }
      }
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((item) =>
                LanSyncConflict.fromJson(Map<String, dynamic>.from(item)))
            .whereType<LanSyncConflict>()
            .toList();
      }
    } catch (_) {
      // 读不出来就当没有冲突
    }
    return <LanSyncConflict>[];
  }

  static Future<void> save(List<LanSyncConflict> conflicts) async {
    try {
      await _db?.optionsBox.put(
        _key,
        jsonEncode(conflicts.map((item) => item.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<void> clear() => save(<LanSyncConflict>[]);
}
