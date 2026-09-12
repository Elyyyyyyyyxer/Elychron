import 'package:celechron/model/task.dart';
import 'package:celechron/model/tombstone.dart';

/// Task / SubTask / 附件 / 评论 的 JSON 编解码。
///
/// 刻意不用 Hive 的字段序号，而是用**稳定的字符串键 + 枚举名**：
/// 序号在版本之间会漂移，跨设备/跨版本同步时会读错字段。
/// 解析时对未知枚举值一律回退到默认值，坏数据不至于让整次导入失败。
class TaskJson {
  TaskJson._();

  // ---------------------------------------------------------------- 枚举

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? name,
    T fallback,
  ) {
    if (name is String) {
      for (final value in values) {
        if (value.name == name) return value;
      }
    }
    return fallback;
  }

  static int _seconds(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  // ------------------------------------------------------------ 子待办等

  static Map<String, dynamic> attachmentToJson(TaskAttachment attachment) => {
        'name': attachment.name,
        'path': attachment.path,
        'size': attachment.size,
      };

  static TaskAttachment attachmentFromJson(Map<String, dynamic> json) =>
      TaskAttachment(
        name: '${json['name'] ?? ''}',
        path: '${json['path'] ?? ''}',
        size: _seconds(json['size'], 0),
      );

  static Map<String, dynamic> commentToJson(TaskComment comment) => {
        'content': comment.content,
        'time': comment.time.toIso8601String(),
      };

  static TaskComment commentFromJson(Map<String, dynamic> json) => TaskComment(
        content: '${json['content'] ?? ''}',
        time: DateTime.tryParse('${json['time']}') ?? DateTime.now(),
      );

  static Map<String, dynamic> subtaskToJson(SubTask subtask) => {
        'uid': subtask.uid,
        'title': subtask.title,
        'done': subtask.done,
        'description': subtask.description,
        // ===== P2：行程型字段（老版本的导出里没有这两个键）=====
        'startTime': subtask.startTime?.toIso8601String(),
        'reminderMinutes': subtask.reminderMinutes,
        'endTime': subtask.endTime?.toIso8601String(),
        'priority': subtask.priority.name,
        'tags': subtask.tags,
        'attachments': subtask.attachments.map(attachmentToJson).toList(),
        'location': subtask.location,
      };

  static SubTask subtaskFromJson(Map<String, dynamic> json) => SubTask(
        uid: json['uid'] is String ? json['uid'] as String : null,
        title: '${json['title'] ?? ''}',
        done: json['done'] == true,
        description: '${json['description'] ?? ''}',
        // 缺失即 null（向后兼容：老导出、老同步包都读得进来）
        startTime: json['startTime'] is String
            ? DateTime.tryParse(json['startTime'] as String)
            : null,
        reminderMinutes: json['reminderMinutes'] is int
            ? json['reminderMinutes'] as int
            : null,
        endTime: DateTime.tryParse('${json['endTime']}'),
        priority: _enumByName(
            TaskPriority.values, json['priority'], TaskPriority.normal),
        tags: _stringList(json['tags']),
        attachments: _attachmentList(json['attachments']),
        location: '${json['location'] ?? ''}',
      );

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return <String>[];
    return raw.whereType<String>().toList();
  }

  static List<TaskAttachment> _attachmentList(Object? raw) {
    if (raw is! List) return <TaskAttachment>[];
    return raw
        .whereType<Map>()
        .map((e) => attachmentFromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ---------------------------------------------------------------- Task

  static Map<String, dynamic> taskToJson(Task task) => {
        'uid': task.uid,
        'status': task.status.name,
        'description': task.description,
        'timeSpent': task.timeSpent.inSeconds,
        'endTime': task.endTime.toIso8601String(),
        'location': task.location,
        'summary': task.summary,
        'type': task.type.name,
        'startTime': task.startTime.toIso8601String(),
        'repeatType': task.repeatType.name,
        'repeatPeriod': task.repeatPeriod,
        'repeatEndsTime': task.repeatEndsTime.toIso8601String(),
        'fromUid': task.fromUid,
        'subtasks': task.subtasks.map(subtaskToJson).toList(),
        'priority': task.priority.name,
        'reminderEnabled': task.reminderEnabled,
        'reminderTime': task.reminderTime?.toIso8601String(),
        'attachments': task.attachments.map(attachmentToJson).toList(),
        'comments': task.comments.map(commentToJson).toList(),
        'tags': task.tags,
        'starred': task.starred,
        'createdAt': task.createdAt?.toIso8601String(),
        'updatedAt': task.updatedAt?.toIso8601String(),
      };

  /// 解析失败（缺少必要时间字段）时返回 null，由调用方跳过这一条。
  static Task? taskFromJson(Map<String, dynamic> json) {
    final uid = json['uid'];
    final startTime = DateTime.tryParse('${json['startTime']}');
    final endTime = DateTime.tryParse('${json['endTime']}');
    final repeatEndsTime = DateTime.tryParse('${json['repeatEndsTime']}');
    if (uid is! String || uid.isEmpty) return null;
    if (startTime == null || endTime == null || repeatEndsTime == null) {
      return null;
    }

    return Task(
      uid: uid,
      status:
          _enumByName(TaskStatus.values, json['status'], TaskStatus.running),
      description: '${json['description'] ?? ''}',
      timeSpent: Duration(seconds: _seconds(json['timeSpent'], 0)),
      endTime: endTime,
      location: '${json['location'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      type: _enumByName(TaskType.values, json['type'], TaskType.deadline),
      startTime: startTime,
      repeatType: _enumByName(
          TaskRepeatType.values, json['repeatType'], TaskRepeatType.norepeat),
      repeatPeriod: _seconds(json['repeatPeriod'], 1),
      repeatEndsTime: repeatEndsTime,
      fromUid: json['fromUid'] is String ? json['fromUid'] as String : null,
      subtasks: _subtaskList(json['subtasks']),
      priority: _enumByName(
          TaskPriority.values, json['priority'], TaskPriority.normal),
      reminderEnabled: json['reminderEnabled'] == true,
      reminderTime: DateTime.tryParse('${json['reminderTime']}'),
      attachments: _attachmentList(json['attachments']),
      comments: _commentList(json['comments']),
      tags: _stringList(json['tags']),
      starred: json['starred'] == true,
      createdAt: DateTime.tryParse('${json['createdAt']}'),
      updatedAt: DateTime.tryParse('${json['updatedAt']}'),
    );
  }

  static List<SubTask> _subtaskList(Object? raw) {
    if (raw is! List) return <SubTask>[];
    return raw
        .whereType<Map>()
        .map((e) => subtaskFromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static List<TaskComment> _commentList(Object? raw) {
    if (raw is! List) return <TaskComment>[];
    return raw
        .whereType<Map>()
        .map((e) => commentFromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ------------------------------------------------------------ 墓碑

  static Map<String, dynamic> tombstoneToJson(TaskTombstone tombstone) =>
      tombstone.toJson();

  static TaskTombstone? tombstoneFromJson(Map<String, dynamic> json) =>
      TaskTombstone.fromJson(json);
}
