import 'dart:convert';

import 'package:celechron/model/task.dart';
import 'package:celechron/model/tombstone.dart';
import 'package:celechron/utils/task_json.dart';

/// 一次完整的数据快照：待办 + 删除墓碑 + 标签库 + 少量设置。
///
/// 这是「导出 / 导入」和后续「多端同步」共用的载体，
/// 本地导出导入跑通之后，把它整份 PUT/GET 到坚果云就是同步。
class DataBundle {
  static const String format = 'celechron-mod';
  static const int version = 1;

  final DateTime exportedAt;
  final List<Task> tasks;
  final List<TaskTombstone> tombstones;
  final List<String> tags;
  final Map<String, int> tagColors;
  final int reminderMode;
  final String alarmTheme;

  const DataBundle({
    required this.exportedAt,
    required this.tasks,
    required this.tombstones,
    required this.tags,
    required this.tagColors,
    required this.reminderMode,
    required this.alarmTheme,
  });

  Map<String, dynamic> toJson() => {
        'format': format,
        'version': version,
        'exportedAt': exportedAt.toIso8601String(),
        'tasks': tasks.map(TaskJson.taskToJson).toList(),
        'tombstones': tombstones.map(TaskJson.tombstoneToJson).toList(),
        'tags': tags,
        'tagColors': tagColors,
        'settings': {
          'reminderMode': reminderMode,
          'alarmTheme': alarmTheme,
        },
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// 解析失败返回 null（文件不是本应用导出的、或内容损坏）
  static DataBundle? decode(String text) {
    Object? raw;
    try {
      raw = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    if (json['format'] != format) return null;

    final tasks = <Task>[];
    final rawTasks = json['tasks'];
    if (rawTasks is List) {
      for (final item in rawTasks) {
        if (item is! Map) continue;
        final task = TaskJson.taskFromJson(Map<String, dynamic>.from(item));
        if (task != null) tasks.add(task);
      }
    }

    final tombstones = <TaskTombstone>[];
    final rawTombstones = json['tombstones'];
    if (rawTombstones is List) {
      for (final item in rawTombstones) {
        if (item is! Map) continue;
        final tombstone =
            TaskJson.tombstoneFromJson(Map<String, dynamic>.from(item));
        if (tombstone != null) tombstones.add(tombstone);
      }
    }

    final tags = <String>[];
    final rawTags = json['tags'];
    if (rawTags is List) tags.addAll(rawTags.whereType<String>());

    final tagColors = <String, int>{};
    final rawColors = json['tagColors'];
    if (rawColors is Map) {
      rawColors.forEach((key, value) {
        if (key is String && value is int) tagColors[key] = value;
      });
    }

    final settings = json['settings'] is Map
        ? Map<String, dynamic>.from(json['settings'] as Map)
        : <String, dynamic>{};

    return DataBundle(
      exportedAt: DateTime.tryParse('${json['exportedAt']}') ?? DateTime.now(),
      tasks: tasks,
      tombstones: tombstones,
      tags: tags,
      tagColors: tagColors,
      reminderMode:
          settings['reminderMode'] is int ? settings['reminderMode'] as int : 0,
      alarmTheme: settings['alarmTheme'] is String
          ? settings['alarmTheme'] as String
          : 'tianyi',
    );
  }
}

/// 合并结果，用于给用户看「新增了几条、更新了几条、删除了几条」
class MergeResult {
  final List<Task> tasks;
  final List<TaskTombstone> tombstones;
  final int added;
  final int updated;
  final int removed;
  final int kept;

  const MergeResult({
    required this.tasks,
    required this.tombstones,
    required this.added,
    required this.updated,
    required this.removed,
    required this.kept,
  });

  String get summary => '新增 $added 条，更新 $updated 条，删除 $removed 条，保留 $kept 条';
}

class DataMerge {
  DataMerge._();

  /// 比较两条待办谁更新；都没有时间戳时退回创建时间/截止时间。
  static DateTime updatedAtOf(Task task) =>
      task.updatedAt ?? task.createdAt ?? task.endTime;

  /// 把 [incoming] 合并进 [local]：
  /// - 同 uid 比 updatedAt，新者胜
  /// - 墓碑时间晚于待办更新时间 → 该待办保持删除
  /// - 墓碑取并集，同 uid 取更晚的时间
  static MergeResult merge({
    required List<Task> local,
    required List<TaskTombstone> localTombstones,
    required DataBundle incoming,
  }) {
    // 墓碑并集
    final tombstones = <String, TaskTombstone>{
      for (final tombstone in localTombstones) tombstone.uid: tombstone,
    };
    for (final tombstone in incoming.tombstones) {
      final existing = tombstones[tombstone.uid];
      if (existing == null || tombstone.deletedAt.isAfter(existing.deletedAt)) {
        tombstones[tombstone.uid] = tombstone;
      }
    }

    final byUid = <String, Task>{for (final task in local) task.uid: task};
    var added = 0;
    var updated = 0;

    for (final remote in incoming.tasks) {
      final tombstone = tombstones[remote.uid];
      if (tombstone != null &&
          !updatedAtOf(remote).isAfter(tombstone.deletedAt)) {
        // 删除晚于最后一次修改：保持删除状态，不要复活
        continue;
      }
      final existing = byUid[remote.uid];
      if (existing == null) {
        byUid[remote.uid] = remote;
        added++;
      } else if (updatedAtOf(remote).isAfter(updatedAtOf(existing))) {
        byUid[remote.uid] = remote;
        updated++;
      }
    }

    // 应用墓碑：删掉被删的待办，以及挂在其上的《过去日程》副本
    final removedUids = <String>{};
    final result = <Task>[];
    for (final task in byUid.values) {
      final tombstone = tombstones[task.uid];
      if (tombstone != null &&
          !updatedAtOf(task).isAfter(tombstone.deletedAt)) {
        removedUids.add(task.uid);
        continue;
      }
      if (task.type == TaskType.fixedlegacy &&
          task.fromUid != null &&
          tombstones.containsKey(task.fromUid)) {
        final parentTombstone = tombstones[task.fromUid!]!;
        if (!updatedAtOf(task).isAfter(parentTombstone.deletedAt)) continue;
      }
      result.add(task);
    }

    result.sort((a, b) => a.endTime.compareTo(b.endTime));

    return MergeResult(
      tasks: result,
      tombstones: tombstones.values.toList(),
      added: added,
      updated: updated,
      removed: removedUids.length,
      kept: result.length - added,
    );
  }
}
