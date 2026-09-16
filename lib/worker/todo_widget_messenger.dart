import 'dart:convert';

import 'package:celechron/model/task.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum TodoWidgetAction { openList, create }

/// Bridges Android widget navigation into the already-mounted home page.
class TodoWidgetActionCenter {
  static final ValueNotifier<TodoWidgetAction?> current =
      ValueNotifier<TodoWidgetAction?>(null);

  static void dispatch(TodoWidgetAction action) {
    current.value = action;
  }
}

/// Writes a compact, platform-neutral task snapshot for the Android widget.
class TodoWidgetMessenger {
  static const _channel = MethodChannel('celechron/todoWidget');
  static const int maxVisibleTasks = 20;

  /// ===== 已尘封：桌面小组件「最近待办」=====
  ///
  /// 2026-09-15 深夜决定尘封（`AndroidManifest.xml` 里的接收器也一并注释掉了，
  /// 所以它不会出现在桌面小组件列表里）。原因见 `docs/WHATS_NEW_1.4.1.md` 11.9：
  /// 在华为鸿蒙上，"勾选后画面不刷新"是系统电池优化挡住了 Glance 的会话任务
  /// （WorkManager）——加白名单能好，但要求每个用户手动去系统里放行，代价太大。
  ///
  /// 代码全部保留、只是不再推数据：把这里改成 `true`、并且把 manifest 里那段
  /// receiver 放回来，功能就回来了（后端逻辑这轮已经全部验证过是对的）。
  static const bool enabled = false;

  static Future<void> update(Iterable<Task> tasks) async {
    if (!enabled) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final snapshot = buildSnapshot(tasks, now: DateTime.now());
      await _channel.invokeMethod<void>('update', jsonEncode(snapshot));
    } on MissingPluginException {
      // Android host is not attached yet (for example during startup/tests).
    } on PlatformException {
      // A widget refresh must never block saving the user's task data.
    }
  }

  static Future<Set<String>> pendingCompletionIds() async {
    if (!enabled) return const <String>{};
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const <String>{};
    }
    try {
      final ids =
          await _channel.invokeListMethod<String>('getPendingCompletions');
      return ids?.toSet() ?? const <String>{};
    } on MissingPluginException {
      return const <String>{};
    } on PlatformException {
      return const <String>{};
    }
  }

  static Future<void> acknowledgeCompletions(Iterable<String> ids) async {
    if (!enabled) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>(
        'ackCompletions',
        ids.toList(growable: false),
      );
    } on MissingPluginException {
      // The next app start will retry the queued actions.
    } on PlatformException {
      // The next app start will retry the queued actions.
    }
  }

  static bool markCompleted(
    Iterable<Task> tasks,
    Set<String> ids, {
    required DateTime now,
  }) {
    var changed = false;
    for (final task in tasks) {
      if (!ids.contains(task.uid) || task.status == TaskStatus.completed) {
        continue;
      }
      task.status = TaskStatus.completed;
      task.updatedAt = now;
      for (final subtask in task.subtasks) {
        subtask.done = true;
      }
      changed = true;
    }
    return changed;
  }

  @visibleForTesting
  static Map<String, Object> buildSnapshot(
    Iterable<Task> tasks, {
    required DateTime now,
  }) {
    final pending = tasks.where(_isPending).toList()
      ..sort((left, right) => _compareTasks(left, right, now));

    return <String, Object>{
      'pendingCount': pending.length,
      'tasks': pending
          .take(maxVisibleTasks)
          .map(
            (task) => <String, Object>{
              'id': task.uid,
              'title': task.summary.trim().isEmpty ? '未命名待办' : task.summary,
              // ===== 小组件自己算文案要用的两个字段 =====
              //
              // `kind` + `at` 是给小组件**在本地按当前时间重算**「今天 10:00 截止」
              // 「已逾期」用的：原来这两句是 App 推快照时算好的，App 不开就永远停在
              // 旧值（用户实测："小组件像是死的"）。`at` 的取值口径与 [_timeLabel]
              // 完全一致（活动取开始、其余取结束），逾期判定也基于它。
              'kind': _kindOf(task),
              if (!task.isMemo) 'at': _timeOf(task).millisecondsSinceEpoch,
              // 下面两个是**兜底**：万一是旧版快照（没有 kind/at），
              // 小组件仍能显示 App 算好的文案，而不是空白。
              'time': _timeLabel(task, now),
              'overdue': _isOverdue(task, now),
            },
          )
          .toList(),
    };
  }

  /// 小组件要区分的四种语义（备忘没有时间）
  static String _kindOf(Task task) {
    if (task.isMemo) return 'memo';
    if (task.isEvent) return 'event';
    if (task.isRemind) return 'remind';
    return 'deadline';
  }

  static DateTime _timeOf(Task task) =>
      task.isEvent ? task.startTime : task.endTime;

  static bool _isPending(Task task) {
    if (task.type == TaskType.fixedlegacy) return false;
    return task.status != TaskStatus.completed &&
        task.status != TaskStatus.deleted &&
        task.status != TaskStatus.outdated;
  }

  static int _compareTasks(Task left, Task right, DateTime now) {
    final leftGroup = _sortGroup(left, now);
    final rightGroup = _sortGroup(right, now);
    if (leftGroup != rightGroup) return leftGroup.compareTo(rightGroup);

    if (left.isMemo && right.isMemo) {
      return right.sortableUpdatedAt.compareTo(left.sortableUpdatedAt);
    }

    final leftTime = _timeOf(left);
    final rightTime = _timeOf(right);
    // For overdue tasks, show the deadline nearest to now first.
    return leftGroup == 0
        ? rightTime.compareTo(leftTime)
        : leftTime.compareTo(rightTime);
  }

  static int _sortGroup(Task task, DateTime now) {
    if (_isOverdue(task, now)) return 0;
    if (!task.isMemo) return 1;
    return 2;
  }

  static String _timeLabel(Task task, DateTime now) {
    if (task.isMemo) return '备忘';

    final time = _timeOf(task);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    String date;
    if (day == today) {
      date = '今天 $clock';
    } else if (day == today.add(const Duration(days: 1))) {
      date = '明天 $clock';
    } else {
      date = '${time.month}月${time.day}日 $clock';
    }

    if (_isOverdue(task, now)) return '已逾期 · $date';
    if (task.isEvent) return '$date 开始';
    if (task.isRemind) return '$date 提醒';
    return '$date 截止';
  }

  static bool _isOverdue(Task task, DateTime now) =>
      task.type == TaskType.deadline && task.endTime.isBefore(now);
}
