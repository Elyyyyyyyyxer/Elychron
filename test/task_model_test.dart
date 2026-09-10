import 'dart:io';

import 'package:celechron/database/adapters/deadline_adapter.dart';
import 'package:celechron/database/adapters/duration_adapter.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('celechron_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(DurationAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(DeadlineAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(DeadlineStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(DeadlineTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(DeadlineRepeatTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(SubTaskAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(TaskAttachmentAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(TaskCommentAdapter());
    }
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(TaskPriorityAdapter());
    }
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Task buildTask() {
    final start = DateTime(2026, 9, 20, 9, 0);
    final task = Task(
      uid: 'task-1',
      summary: '写完论文',
      description: '把第三章补完',
      startTime: start,
      endTime: start.add(const Duration(days: 1)),
      repeatEndsTime: start,
    );
    task.reset();
    task.uid = 'task-1';
    task.summary = '写完论文';
    task.description = '把第三章补完';
    task.startTime = start;
    task.endTime = start.add(const Duration(days: 1));
    task.priority = TaskPriority.urgent;
    task.reminderEnabled = true;
    task.reminderTime = start.subtract(const Duration(hours: 2));
    task.subtasks = [
      SubTask(uid: 'sub-1', title: '列提纲', done: true),
      SubTask(uid: 'sub-2', title: '写正文'),
      SubTask(uid: 'sub-3', title: '校对'),
    ];
    task.attachments = [
      TaskAttachment(name: 'ref.pdf', path: '/tmp/ref.pdf', size: 2048),
    ];
    task.comments = [
      TaskComment(content: '导师说要加实验', time: DateTime(2026, 9, 19, 20)),
    ];
    task.tags = ['论文', '重要'];
    return task;
  }

  test('子待办进度计算正确', () {
    final task = buildTask();
    expect(task.subtasks.length, 3);
    expect(task.subtaskDoneCount, 1);
    expect(task.subtaskProgress, closeTo(1 / 3, 1e-9));

    task.subtasks[1].done = true;
    expect(task.subtaskDoneCount, 2);
    expect(task.subtaskProgress, closeTo(2 / 3, 1e-9));
  });

  test('提醒时间缺省回落到截止时间', () {
    final task = buildTask();
    expect(task.reminderTargetTime, task.reminderTime);

    task.reminderTime = null;
    expect(task.reminderTargetTime, task.endTime);
  });

  test('新字段能写入 Hive 并原样读回', () async {
    final box = await Hive.openBox('tasks');
    await box.put('list', [buildTask()]);

    final loaded = List<Task>.from(box.get('list') as List);
    expect(loaded.length, 1);

    final task = loaded.first;
    expect(task.summary, '写完论文');
    expect(task.priority, TaskPriority.urgent);
    expect(task.reminderEnabled, isTrue);
    expect(task.reminderTime, DateTime(2026, 9, 20, 7, 0));
    expect(task.subtasks.map((e) => e.title).toList(), ['列提纲', '写正文', '校对']);
    expect(task.subtasks.map((e) => e.done).toList(), [true, false, false]);
    expect(task.subtasks.first.uid, 'sub-1');
    expect(task.attachments.single.name, 'ref.pdf');
    expect(task.attachments.single.size, 2048);
    expect(task.comments.single.content, '导师说要加实验');
    expect(task.comments.single.time, DateTime(2026, 9, 19, 20));
    expect(task.tags, ['论文', '重要']);
  });

  test('copyWith 深拷贝列表，互不影响', () {
    final original = buildTask();
    final clone = original.copyWith();

    clone.subtasks.add(SubTask(title: '新条目'));
    clone.subtasks.first.title = '改过的标题';
    clone.attachments.clear();
    clone.comments.clear();
    clone.tags.clear();

    expect(original.subtasks.length, 3);
    expect(original.subtasks.first.title, '列提纲');
    expect(original.attachments.length, 1);
    expect(original.comments.length, 1);
    expect(original.tags.length, 2);
  });

  test('重复推进：每天 / 每周工作日 / 每 N 月 / 每 N 年', () {
    Task make(TaskRepeatType type, int period, DateTime start) {
      final task = Task(
        startTime: start,
        endTime: start.add(const Duration(hours: 2)),
        repeatEndsTime: kRepeatEndlessDate,
      );
      task.repeatType = type;
      task.repeatPeriod = period;
      return task;
    }

    // 每天
    var task = make(TaskRepeatType.days, 1, DateTime(2026, 9, 7, 9));
    expect(task.advanceRepeatPeriod(), isTrue);
    expect(task.startTime, DateTime(2026, 9, 8, 9));
    expect(task.endTime, DateTime(2026, 9, 8, 11));

    // 每周工作日：周三 → 周四
    task = make(TaskRepeatType.weekday, 1, DateTime(2026, 9, 9, 9));
    task.advanceRepeatPeriod();
    expect(task.startTime, DateTime(2026, 9, 10, 9));

    // 每周工作日：周五 → 下周一（跳过双休日）
    task = make(TaskRepeatType.weekday, 1, DateTime(2026, 9, 11, 9));
    task.advanceRepeatPeriod();
    expect(task.startTime, DateTime(2026, 9, 14, 9));

    // 每 2 月
    task = make(TaskRepeatType.month, 2, DateTime(2026, 9, 15, 9));
    task.advanceRepeatPeriod();
    expect(task.startTime, DateTime(2026, 11, 15, 9));

    // 每 3 年
    task = make(TaskRepeatType.year, 3, DateTime(2026, 9, 15, 9));
    task.advanceRepeatPeriod();
    expect(task.startTime, DateTime(2029, 9, 15, 9));

    // 推进后越过重复结束日期 → 标记为已过期
    task = make(TaskRepeatType.days, 1, DateTime(2026, 9, 15, 9));
    task.repeatEndsTime = DateTime(2026, 9, 15);
    task.advanceRepeatPeriod();
    expect(task.status, TaskStatus.outdated);
  });

  test('无限重复哨兵值判定', () {
    expect(isRepeatEndless(kRepeatEndlessDate), isTrue);
    expect(isRepeatEndless(DateTime(2026, 9, 20)), isFalse);
  });

  test('老数据（无新字段）读取后使用默认值', () async {
    // 模拟 v1.2.0 的旧对象：只有前 16 个字段
    final box = await Hive.openBox('legacy');
    final legacy = buildTask();
    legacy.subtasks = [];
    legacy.attachments = [];
    legacy.comments = [];
    legacy.priority = TaskPriority.normal;
    legacy.reminderEnabled = false;
    legacy.reminderTime = null;
    legacy.tags = [];
    await box.put('list', [legacy]);

    final loaded = List<Task>.from(box.get('list') as List).first;
    expect(loaded.subtasks, isEmpty);
    expect(loaded.priority, TaskPriority.normal);
    expect(loaded.reminderEnabled, isFalse);
    expect(loaded.reminderTime, isNull);
    expect(loaded.subtaskProgress, 0.0);
  });
}
