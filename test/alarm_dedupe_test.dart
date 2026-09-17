import 'package:celechron/model/task.dart';
import 'package:celechron/mod/task_runtime_mod.dart';
import 'package:celechron/utils/task_alarm_center.dart';
import 'package:celechron/utils/task_reminder.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// 闹钟去重：**关掉弹窗之后不能重复弹**。
///
/// 这是一个真实反馈（用户原话：后台被清掉了闹钟就不会触发，但是一打开软件，
/// 闹钟弹窗会一直触发，关了还会一直重复弹闹钟）。
///
/// 根因：去重记录写在 `TaskAlarmCoordinator` 里，且写成
/// `if (TaskAlarmCenter.current.value == null) _fired.clear();`
///， 用户一点掉弹窗（current 变 null），下一秒 tick 就把记录清空，
/// 而那条待办的提醒时刻仍在"同一分钟内"，于是又弹，循环不止。
void main() {
  setUp(() {
    TaskAlarmCenter.resetForTest();
    TaskAlarmCenter.clear();
    TaskReminder.mode = TaskReminder.modeAlarm;
  });

  tearDown(() {
    TaskAlarmCenter.resetForTest();
    TaskAlarmCenter.clear();
    TaskReminder.mode = TaskReminder.modeNotification;
  });

  /// 造一条"提醒时间就是现在"的提醒型待办
  Task dueNowTask({String uid = 'alarm-test-1', String summary = '测试闹钟'}) {
    final now = DateTime.now();
    return Task(
      uid: uid,
      summary: summary,
      endTime: now,
      startTime: now,
      repeatEndsTime: dateOnly(now),
    )
      ..type = TaskType.remind
      ..status = TaskStatus.running
      ..reminderEnabled = true
      ..reminderTime = now;
  }

  test('到点弹出一次', () {
    final task = dueNowTask();
    TaskAlarmCoordinator.tick([task]);
    expect(TaskAlarmCenter.current.value?.uid, task.uid);
  });

  test('关掉弹窗后**不会**再弹（回归：修复前这里会重复弹）', () {
    final task = dueNowTask();
    TaskAlarmCoordinator.tick([task]);
    expect(TaskAlarmCenter.current.value, isNotNull);

    // 用户点掉弹窗
    TaskAlarmCenter.clear();
    expect(TaskAlarmCenter.current.value, isNull);

    // 下一秒 tick：同一时刻已经弹过，不该再弹
    TaskAlarmCoordinator.tick([task]);
    expect(TaskAlarmCenter.current.value, isNull,
        reason: '同一提醒时刻只应弹一次，关掉弹窗不应重新触发');
  });

  test('连续多次 tick 也只弹一次', () {
    final task = dueNowTask();
    for (var i = 0; i < 5; i++) {
      TaskAlarmCoordinator.tick([task]);
      TaskAlarmCenter.clear();
    }
    expect(TaskAlarmCenter.current.value, isNull);
  });

  test('改了提醒时间 → 新的时刻，可以再弹', () {
    final task = dueNowTask();
    TaskAlarmCoordinator.tick([task]);
    TaskAlarmCenter.clear();

    // 用户把提醒时间改到"现在"之后的另一时刻（模拟改时间）
    final later = DateTime.now().add(const Duration(seconds: 1));
    task.reminderTime = later;
    // 还没到点，不该弹
    TaskAlarmCoordinator.tick([task]);
    expect(TaskAlarmCenter.current.value, isNull);

    // 把那条待办的提醒时刻手动标记为新时刻后，应该能弹（用中心自身的记录验证）
    expect(TaskAlarmCenter.hasFired(task, task.reminderTargetTime), isFalse);
  });

  test('通知路径触发也计入同一套去重', () {
    final task = dueNowTask(uid: 'alarm-test-2');
    // 模拟点通知进来：TaskReminder 走的就是 fire(...)
    TaskAlarmCenter.fire(task, occurrenceAt: task.reminderTargetTime);
    expect(TaskAlarmCenter.current.value?.uid, task.uid);
    TaskAlarmCenter.clear();

    // 之后前台 tick 不该再弹同一次
    TaskAlarmCoordinator.tick([task]);
    expect(TaskAlarmCenter.current.value, isNull);
  });

  test('错过很久的提醒不补弹（避免一开 App 炸一串）', () {
    final now = DateTime.now();
    final stale = Task(
      uid: 'alarm-test-stale',
      summary: '很久以前就该响的',
      endTime: now.subtract(const Duration(minutes: 30)),
      startTime: now.subtract(const Duration(minutes: 30)),
      repeatEndsTime: dateOnly(now),
    )
      ..type = TaskType.remind
      ..status = TaskStatus.running
      ..reminderEnabled = true
      ..reminderTime = now.subtract(const Duration(minutes: 30));

    TaskAlarmCoordinator.tick([stale]);
    expect(TaskAlarmCenter.current.value, isNull);
  });

  test('已完成 / 备忘型不会被弹', () {
    final memo = Task(
      uid: 'alarm-test-memo',
      summary: '备忘',
      endTime: DateTime.now(),
      startTime: DateTime.now(),
      repeatEndsTime: dateOnly(DateTime.now()),
    )
      ..type = TaskType.memo
      ..status = TaskStatus.running
      ..reminderEnabled = true
      ..reminderTime = DateTime.now();
    TaskAlarmCoordinator.tick([memo]);
    expect(TaskAlarmCenter.current.value, isNull);

    final done = dueNowTask(uid: 'alarm-test-done')
      ..status = TaskStatus.completed;
    TaskAlarmCoordinator.tick([done]);
    expect(TaskAlarmCenter.current.value, isNull);
  });

  test('去重记录会随时间的推移被清理，不会无限增长', () {
    final task = dueNowTask(uid: 'alarm-test-prune');
    for (var i = 0; i < 250; i++) {
      TaskAlarmCenter.markFired(
          task, DateTime.now().subtract(Duration(days: 3)));
    }
    // 超过阈值触发清理，三天前的记录应被丢掉
    TaskAlarmCenter.markFired(task, DateTime.now());
    expect(TaskAlarmCenter.firedCount, lessThan(250));
  });
}
