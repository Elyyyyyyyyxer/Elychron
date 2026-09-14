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

  static Future<void> update(Iterable<Task> tasks) async {
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

  @visibleForTesting
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
              'time': _timeLabel(task, now),
              'overdue': _isOverdue(task, now),
            },
          )
          .toList(),
    };
  }

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

    final leftTime = left.isEvent ? left.startTime : left.endTime;
    final rightTime = right.isEvent ? right.startTime : right.endTime;
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

    final time = task.isEvent ? task.startTime : task.endTime;
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
