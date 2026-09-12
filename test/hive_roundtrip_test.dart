import 'dart:io';

import 'package:celechron/database/adapters/deadline_adapter.dart';
import 'package:celechron/database/adapters/duration_adapter.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// P5：**Hive 存储往返测试**。
///
/// 为什么值得单独写：Hive 是靠**字段序号**读写记录的，我们刚把「时间规划」的三个
/// 死字段（序号 4 / 8 / 14）从写入里去掉。这类改动的风险不在逻辑，而在
/// 「序号写错一位 → 老数据被读成别的字段」，而且**运行时不会报错、只会静默错位**。
///
/// 这里用一个真的 Hive 盒子（临时目录）把整条 Task（含子待办/附件/评论）写进去再读回来，
/// 逐个字段比对 —— 序号一旦错位，这个测试立刻红。
void main() {
  late Directory tempDir;
  late Box<Task> box;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('elychron_hive_roundtrip');
    Hive.init(tempDir.path);
    Hive.registerAdapter(DurationAdapter());
    Hive.registerAdapter(DeadlineStatusAdapter());
    Hive.registerAdapter(DeadlineTypeAdapter());
    Hive.registerAdapter(DeadlineRepeatTypeAdapter());
    Hive.registerAdapter(TaskPriorityAdapter());
    Hive.registerAdapter(SubTaskAdapter());
    Hive.registerAdapter(TaskAttachmentAdapter());
    Hive.registerAdapter(TaskCommentAdapter());
    Hive.registerAdapter(DeadlineAdapter());
    box = await Hive.openBox<Task>('roundtrip');
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('整条 Task 写进去再读回来，每个字段都还在原位', () async {
    final task = Task(
      uid: 'uid-1',
      summary: '班级团建',
      description: '带身份证',
      endTime: DateTime(2026, 9, 12, 22, 0),
      startTime: DateTime(2026, 9, 12, 18, 0),
      repeatEndsTime: DateTime(2026, 9, 12),
      location: '龙湖西溪天街',
      priority: TaskPriority.high,
      starred: true,
      reminderEnabled: true,
      reminderTime: DateTime(2026, 9, 12, 17, 30),
      createdAt: DateTime(2026, 9, 1, 9, 0),
      updatedAt: DateTime(2026, 9, 2, 10, 30),
    )
      ..type = TaskType.fixed
      ..status = TaskStatus.running
      ..timeSpent = const Duration(minutes: 47)
      ..repeatType = TaskRepeatType.days
      ..repeatPeriod = 7
      ..fromUid = 'parent-uid'
      ..tags = ['团建', '班级活动']
      ..subtasks = [
        SubTask(
          title: '南出入口集合',
          done: true,
          description: '带身份证',
          location: '南出入口',
          startTime: DateTime(2026, 9, 12, 18, 0),
          endTime: DateTime(2026, 9, 12, 18, 10),
          reminderMinutes: 30,
        ),
      ]
      ..attachments = [TaskAttachment(name: 'a.png', path: '/tmp/a.png', size: 123)]
      ..comments = [TaskComment(content: '记得带伞', time: DateTime(2026, 9, 2))];

    await box.put(task.uid, task);
    final back = box.get('uid-1')!;

    expect(back.uid, 'uid-1');
    expect(back.summary, '班级团建');
    expect(back.description, '带身份证');
    expect(back.endTime, DateTime(2026, 9, 12, 22, 0));
    expect(back.startTime, DateTime(2026, 9, 12, 18, 0));
    expect(back.repeatEndsTime, DateTime(2026, 9, 12));
    expect(back.location, '龙湖西溪天街');
    expect(back.type, TaskType.fixed);
    expect(back.status, TaskStatus.running);
    // 序号 3 的 timeSpent 现在是「专注累计」，必须还读得对
    expect(back.timeSpent, const Duration(minutes: 47));
    expect(back.repeatType, TaskRepeatType.days);
    expect(back.repeatPeriod, 7);
    expect(back.fromUid, 'parent-uid');
    expect(back.priority, TaskPriority.high);
    expect(back.starred, isTrue);
    expect(back.reminderEnabled, isTrue);
    expect(back.reminderTime, DateTime(2026, 9, 12, 17, 30));
    expect(back.createdAt, DateTime(2026, 9, 1, 9, 0));
    expect(back.updatedAt, DateTime(2026, 9, 2, 10, 30));
    expect(back.tags, ['团建', '班级活动']);

    // 子待办（含 P2 的两个新字段）
    expect(back.subtasks.length, 1);
    final sub = back.subtasks.single;
    expect(sub.title, '南出入口集合');
    expect(sub.done, isTrue);
    expect(sub.description, '带身份证');
    expect(sub.location, '南出入口');
    expect(sub.startTime, DateTime(2026, 9, 12, 18, 0));
    expect(sub.endTime, DateTime(2026, 9, 12, 18, 10));
    expect(sub.reminderMinutes, 30);

    expect(back.attachments.single.name, 'a.png');
    expect(back.attachments.single.size, 123);
    expect(back.comments.single.content, '记得带伞');
  });

  test('没有子待办/附件/评论的空任务也不会因为空集合读错', () async {
    final bare = Task(
      uid: 'uid-2',
      summary: '备忘',
      endTime: DateTime(2026, 9, 20, 23, 59),
      startTime: DateTime(2026, 9, 20, 23, 59),
      repeatEndsTime: DateTime(2026, 9, 20),
    )..type = TaskType.memo;

    await box.put(bare.uid, bare);
    final back = box.get('uid-2')!;
    expect(back.type, TaskType.memo);
    expect(back.subtasks, isEmpty);
    expect(back.attachments, isEmpty);
    expect(back.comments, isEmpty);
    expect(back.tags, isEmpty);
    expect(back.timeSpent, Duration.zero);
  });
}
