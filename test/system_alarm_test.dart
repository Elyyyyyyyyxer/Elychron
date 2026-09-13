import 'package:celechron/model/task.dart';
import 'package:celechron/mod/system_alarm.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「把待办交给系统闹钟」的挑选规则。
///
/// 这个功能只做手动入口，所以**挑错待办**是主要风险：把备忘型或已过期的列出来，
/// 用户点了会得到"立刻响"或"根本不该响"的闹钟。
void main() {
  final now = DateTime(2026, 9, 13, 9, 0);

  Task task({
    String summary = '考试',
    TaskStatus status = TaskStatus.running,
    TaskType type = TaskType.deadline,
    bool reminderEnabled = false,
    DateTime? reminderTime,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    // Task 的构造参数是命名式的，endTime / startTime / repeatEndsTime 都是必填
    final end = endTime ?? DateTime(2026, 9, 14, 9, 0);
    return Task(
      summary: summary,
      status: status,
      type: type,
      reminderEnabled: reminderEnabled,
      reminderTime: reminderTime,
      startTime: startTime ?? end,
      endTime: end,
      repeatEndsTime: end,
    );
  }

  test('有提醒时间 → 用提醒时刻（用户明确设过的）', () {
    final t = task(
      reminderEnabled: true,
      reminderTime: DateTime(2026, 9, 13, 16, 45),
      endTime: DateTime(2026, 9, 13, 20, 30),
    );
    expect(systemAlarmTimeFor(t, now), DateTime(2026, 9, 13, 16, 45));
  });

  test('活动型没有提醒 → 锚开始时刻', () {
    final t = task(
      type: TaskType.fixed,
      startTime: DateTime(2026, 9, 13, 17, 45),
      endTime: DateTime(2026, 9, 13, 20, 30),
    );
    expect(systemAlarmTimeFor(t, now), DateTime(2026, 9, 13, 17, 45));
  });

  test('截止型没有提醒 → 用截止时刻', () {
    final t = task(endTime: DateTime(2026, 9, 14, 23, 59));
    expect(systemAlarmTimeFor(t, now), DateTime(2026, 9, 14, 23, 59));
  });

  test('备忘型不提醒 → 不适合', () {
    final t = task(type: TaskType.memo, endTime: DateTime(2026, 9, 14, 9, 0));
    expect(systemAlarmTimeFor(t, now), isNull);
  });

  test('已完成 / 已删除 → 不适合', () {
    final done = task(
      status: TaskStatus.completed,
      endTime: DateTime(2026, 9, 14, 9, 0),
    );
    final deleted = task(
      status: TaskStatus.deleted,
      endTime: DateTime(2026, 9, 14, 9, 0),
    );
    expect(systemAlarmTimeFor(done, now), isNull);
    expect(systemAlarmTimeFor(deleted, now), isNull);
  });

  test('时间已经过去 / 就在此刻 → 不适合（系统闹钟设到过去只会立刻响）', () {
    final past = task(endTime: DateTime(2026, 9, 13, 8, 0));
    final justNow = task(endTime: DateTime(2026, 9, 13, 9, 0));
    final oneMinute = task(endTime: DateTime(2026, 9, 13, 9, 1));
    expect(systemAlarmTimeFor(past, now), isNull);
    expect(systemAlarmTimeFor(justNow, now), isNull);
    // 只剩一分钟也来不及，同样排除
    expect(systemAlarmTimeFor(oneMinute, now), isNull);
  });

  test('再过两分钟就可以（留了余量）', () {
    final t = task(endTime: DateTime(2026, 9, 13, 9, 2));
    expect(systemAlarmTimeFor(t, now), DateTime(2026, 9, 13, 9, 2));
  });

  test('闹钟标题带品牌前缀，时钟里能认出是谁设的', () {
    expect(systemAlarmLabelFor(task(summary: '交作业')), 'Elychron · 交作业');
    expect(systemAlarmLabelFor(task(summary: '   ')), 'Elychron · 待办');
  });
}
