import 'dart:convert';

import 'package:celechron/model/focus_session.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/tombstone.dart';
import 'package:celechron/utils/task_json.dart';

/// ===== 同步用的「密钥白名单」=====
///
/// 只有这里列出的键才允许进 [DataBundle.secrets]。**教务网账号密码永远不在这里** ——
/// 这是机制上的保证：就算以后有人手滑把凭据塞进 secrets，[DataBundle] 也会把它过滤掉。
///
/// 用「字符串键 + 映射」而不是一个个字段，是为了**以后加新 key 不用改契约**：
/// 高德、坚果云（WebDAV）的键都已经留好位置了。
class SyncSecrets {
  SyncSecrets._();

  /// AI（DeepSeek）key
  static const String aiApiKey = 'ai.apiKey';

  /// 高德 Web 服务 key —— 导航时间计算用（功能还没做，键先留好）
  static const String amapKey = 'nav.amapKey';

  /// 坚果云 / WebDAV 的三个字段（跨网络同步那条路线用）
  static const String webdavUrl = 'sync.webdav.url';
  static const String webdavUsername = 'sync.webdav.username';
  static const String webdavPassword = 'sync.webdav.password';

  static const Set<String> allowed = <String>{
    aiApiKey,
    amapKey,
    webdavUrl,
    webdavUsername,
    webdavPassword,
  };

  /// 只保留白名单里的键（值是 String）
  static Map<String, String> filter(Map<String, String> raw) {
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (allowed.contains(key) && value.isNotEmpty) result[key] = value;
    });
    return result;
  }
}

/// 一次完整的数据快照。
///
/// **同步范围**（2026-09-12 与用户确认）：
/// - 要：待办（含子待办/评论/附件条目）+ 删除墓碑 + 标签库与颜色 + 各种设置 +
///   专注记录与专注参数 + 课程代码自定义映射 + **白名单内的密钥**
/// - 不要：从学校服务器拉下来的课表/考试/成绩/校园卡（各端各自去拉最干净）、
///   教务网账号密码、诊断日志
///
/// 这是「导出 / 导入」和「多端同步」共用的载体 —— 本地导出导入跑通之后，
/// 把它整份 PUT/GET 到坚果云就是跨网络同步。
class DataBundle {
  static const String format = 'celechron-mod';

  /// 契约版本：2 = 加了 deviceId / 专注记录 / 更多设置 / 密钥白名单
  ///
  /// 只加字段、不改老字段 —— 所以 version 1 的老备份**照样能导入** ✓
  static const int version = 2;

  final DateTime exportedAt;

  /// 这份快照来自哪台设备（[DataBundle.deviceId] 为空表示老版本导出的）
  final String deviceId;

  final List<Task> tasks;
  final List<TaskTombstone> tombstones;
  final List<String> tags;
  final Map<String, int> tagColors;
  final int reminderMode;
  final String alarmTheme;

  // ===== S1 新增：用户数据里的其余部分 =====
  final List<FocusSession> focusSessions;
  final int focusWorkMinutes;
  final int focusRestMinutes;
  final bool focusRestNotify;
  final int reminderLeadMinutes;
  final int brightnessMode;
  /// 课程代码自定义映射（用户在设置里手配的，所以要同步）。用 CourseIdMap 的 JSON 形式。
  final List<Map<String, dynamic>> courseIdMapping;

  /// 白名单内的密钥（见 [SyncSecrets]）。**用户可关掉密钥同步**，关掉时这里是空的。
  final Map<String, String> secrets;

  const DataBundle({
    required this.exportedAt,
    this.deviceId = '',
    required this.tasks,
    required this.tombstones,
    required this.tags,
    required this.tagColors,
    required this.reminderMode,
    required this.alarmTheme,
    this.focusSessions = const <FocusSession>[],
    this.focusWorkMinutes = 60,
    this.focusRestMinutes = 15,
    this.focusRestNotify = true,
    this.reminderLeadMinutes = 30,
    this.brightnessMode = 0,
    this.courseIdMapping = const <Map<String, dynamic>>[],
    this.secrets = const <String, String>{},
  });

  Map<String, dynamic> toJson() => {
        'format': format,
        'version': version,
        'exportedAt': exportedAt.toIso8601String(),
        'deviceId': deviceId,
        'tasks': tasks.map(TaskJson.taskToJson).toList(),
        'tombstones': tombstones.map(TaskJson.tombstoneToJson).toList(),
        'tags': tags,
        'tagColors': tagColors,
        'focusSessions':
            focusSessions.map((session) => session.toJson()).toList(),
        'secrets': SyncSecrets.filter(secrets),
        'settings': {
          'reminderMode': reminderMode,
          'alarmTheme': alarmTheme,
          'focusWorkMinutes': focusWorkMinutes,
          'focusRestMinutes': focusRestMinutes,
          'focusRestNotify': focusRestNotify,
          'reminderLeadMinutes': reminderLeadMinutes,
          'brightnessMode': brightnessMode,
          'courseIdMapping': courseIdMapping,
        },
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static int _int(Object? raw, int fallback) =>
      raw is int ? raw : (raw is num ? raw.toInt() : fallback);

  static bool _bool(Object? raw, bool fallback) =>
      raw is bool ? raw : fallback;

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

    // 专注记录（老备份没有这一段 → 空列表 ✓）
    final focusSessions = <FocusSession>[];
    final rawSessions = json['focusSessions'];
    if (rawSessions is List) {
      for (final item in rawSessions) {
        if (item is! Map) continue;
        try {
          focusSessions
              .add(FocusSession.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // 单条坏了不影响整包
        }
      }
    }

    // 密钥：**只认白名单**（就算包里塞了别的键也进不来）
    final secrets = <String, String>{};
    final rawSecrets = json['secrets'];
    if (rawSecrets is Map) {
      rawSecrets.forEach((key, value) {
        if (key is String && value is String) secrets[key] = value;
      });
    }

    final settings = json['settings'] is Map
        ? Map<String, dynamic>.from(json['settings'] as Map)
        : <String, dynamic>{};

    final courseIdMapping = <Map<String, dynamic>>[];
    final rawMapping = settings['courseIdMapping'];
    if (rawMapping is List) {
      for (final item in rawMapping) {
        if (item is Map) courseIdMapping.add(Map<String, dynamic>.from(item));
      }
    }

    return DataBundle(
      exportedAt: DateTime.tryParse('${json['exportedAt']}') ?? DateTime.now(),
      deviceId: json['deviceId'] is String ? json['deviceId'] as String : '',
      tasks: tasks,
      tombstones: tombstones,
      tags: tags,
      tagColors: tagColors,
      reminderMode: _int(settings['reminderMode'], 0),
      alarmTheme: settings['alarmTheme'] is String
          ? settings['alarmTheme'] as String
          : 'tianyi',
      focusSessions: focusSessions,
      focusWorkMinutes: _int(settings['focusWorkMinutes'], 60),
      focusRestMinutes: _int(settings['focusRestMinutes'], 15),
      focusRestNotify: _bool(settings['focusRestNotify'], true),
      reminderLeadMinutes: _int(settings['reminderLeadMinutes'], 30),
      brightnessMode: _int(settings['brightnessMode'], 0),
      courseIdMapping: courseIdMapping,
      secrets: SyncSecrets.filter(secrets),
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

  /// ===== S1：附带合并回来的其它数据 =====
  final List<FocusSession> focusSessions;

  /// 本端设置是否被对方覆盖了（设置项按「谁导出的更晚谁说了算」整组替换）
  final bool settingsTakenFromRemote;

  /// 两边都改过、最后按时间取舍的待办 uid（**如实汇报，不静默丢弃**）
  final List<String> conflictUids;

  const MergeResult({
    required this.tasks,
    required this.tombstones,
    required this.added,
    required this.updated,
    required this.removed,
    required this.kept,
    this.focusSessions = const <FocusSession>[],
    this.settingsTakenFromRemote = false,
    this.conflictUids = const <String>[],
  });

  String get summary => '新增 $added 条，更新 $updated 条，删除 $removed 条，保留 $kept 条';
}

class DataMerge {
  DataMerge._();

  /// 比较两条待办谁更新；都没有时间戳时退回创建时间/截止时间。
  static DateTime updatedAtOf(Task task) =>
      task.updatedAt ?? task.createdAt ?? task.endTime;

  /// 合并专注记录。
  ///
  /// 规则（简单且可预期）：
  /// - 只在本端有的 → 保留；只在对方有的 → 加入（按 uid 去重）
  /// - 同 uid 两边都有 → **本端还在跑（`endedAt == null`）就以本端为准**
  ///   （会话的归属设备才有发言权），否则比 `endedAt`，晚的赢
  ///
  /// ⚠️ 已知局限：**专注记录的「删除」不参与同步**（没有会话墓碑），
  /// 所以在一端长按删掉的记录，可能被另一端同步回来。留到下一阶段补。
  static List<FocusSession> mergeFocusSessions({
    required List<FocusSession> local,
    required List<FocusSession> remote,
  }) {
    final byUid = <String, FocusSession>{
      for (final session in local) session.uid: session,
    };
    for (final incoming in remote) {
      final existing = byUid[incoming.uid];
      if (existing == null) {
        byUid[incoming.uid] = incoming;
        continue;
      }
      if (existing.isRunning) continue; // 本端还在跑：以本端为准
      final localEnd = existing.endedAt;
      final remoteEnd = incoming.endedAt;
      if (remoteEnd == null) {
        byUid[incoming.uid] = incoming; // 对方在跑而我们这条已经结束了
        continue;
      }
      if (localEnd == null || remoteEnd.isAfter(localEnd)) {
        byUid[incoming.uid] = incoming;
      }
    }
    final list = byUid.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  /// 把 [incoming] 合并进 [local]：
  /// - 同 uid 比 updatedAt，新者胜
  /// - 墓碑时间晚于待办更新时间 → 该待办保持删除
  /// - 墓碑取并集，同 uid 取更晚的时间
  /// - 专注记录见 [mergeFocusSessions]；设置整组按「谁导出得更晚」取舍
  static MergeResult merge({
    required List<Task> local,
    required List<TaskTombstone> localTombstones,
    required DataBundle incoming,
    List<FocusSession> localFocusSessions = const <FocusSession>[],
    DateTime? localExportedAt,
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
    final conflicts = <String>[];

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
        // 两边都改过（本端也动过、且不是刚创建）→ 记一笔冲突，界面要如实告诉用户
        final localUpdated = existing.updatedAt;
        final localCreated = existing.createdAt;
        if (localUpdated != null &&
            (localCreated == null || localUpdated != localCreated)) {
          conflicts.add(remote.uid);
        }
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
      focusSessions: mergeFocusSessions(
        local: localFocusSessions,
        remote: incoming.focusSessions,
      ),
      // 设置项是一个整体，按「谁导出的更晚」取舍（两端同时改设置的场景极少，
      // 而且设置项都很小，冲突代价远低于逐项比较的复杂度）
      settingsTakenFromRemote: localExportedAt == null ||
          incoming.exportedAt.isAfter(localExportedAt),
      conflictUids: conflicts,
    );
  }
}
