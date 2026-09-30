import 'package:celechron/model/task.dart';
import 'package:celechron/model/tombstone.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:celechron/utils/task_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Task buildTask({
    String uid = 'uid-1',
    String summary = '写给自己的一封信',
    TaskStatus status = TaskStatus.running,
    TaskType type = TaskType.deadline,
    TaskPriority priority = TaskPriority.high,
    TaskRepeatType repeatType = TaskRepeatType.days,
    int repeatPeriod = 2,
    bool starred = true,
    DateTime? updatedAt,
  }) {
    final end = DateTime(2026, 9, 11, 22, 0);
    final task = Task(
      uid: uid,
      summary: summary,
      description: '描述\n第二行',
      endTime: end,
      startTime: DateTime(2026, 9, 10, 23, 59),
      repeatEndsTime: DateTime(2026, 12, 31),
      type: type,
      status: status,
      priority: priority,
      repeatType: repeatType,
      repeatPeriod: repeatPeriod,
      location: '宿舍',
      starred: starred,
      reminderEnabled: true,
      reminderTime: DateTime(2026, 9, 11, 21, 30),
      updatedAt: updatedAt ?? DateTime(2026, 9, 10, 12, 0),
      createdAt: DateTime(2026, 9, 9, 9, 0),
    );
    task.tags.addAll(['学习', '紧急']);
    task.subtasks.add(SubTask(title: '子任务 A', done: true));
    task.subtasks.add(SubTask(
      title: '子任务 B',
      description: '子描述',
      endTime: DateTime(2026, 9, 11, 20, 0),
      priority: TaskPriority.urgent,
      tags: ['子标签'],
      location: '图书馆',
    ));
    task.attachments
        .add(TaskAttachment(name: 'a.png', path: '/tmp/a.png', size: 12));
    task.comments
        .add(TaskComment(content: '备注', time: DateTime(2026, 9, 10, 8, 0)));
    return task;
  }

  DataBundle bundleOf(List<Task> tasks,
          {List<TaskTombstone> tombstones = const []}) =>
      DataBundle(
        exportedAt: DateTime(2026, 9, 10, 20, 0),
        tasks: tasks,
        tombstones: tombstones,
        tags: ['学习', '紧急'],
        tagColors: {'学习': 0xFF007AFF},
        reminderMode: 1,
        alarmTheme: 'elysia',
      );

  group('JSON 往返', () {
    test('所有字段与嵌套结构都能完整还原', () {
      final task = buildTask();
      final restored = TaskJson.taskFromJson(TaskJson.taskToJson(task))!;

      expect(restored.uid, task.uid);
      expect(restored.summary, task.summary);
      expect(restored.description, task.description);
      expect(restored.startTime, task.startTime);
      expect(restored.endTime, task.endTime);
      expect(restored.repeatEndsTime, task.repeatEndsTime);
      expect(restored.repeatType, task.repeatType);
      expect(restored.repeatPeriod, task.repeatPeriod);
      expect(restored.type, task.type);
      expect(restored.status, task.status);
      expect(restored.priority, task.priority);
      expect(restored.location, task.location);
      expect(restored.starred, task.starred);
      expect(restored.reminderEnabled, task.reminderEnabled);
      expect(restored.reminderTime, task.reminderTime);
      expect(restored.createdAt, task.createdAt);
      expect(restored.updatedAt, task.updatedAt);
      expect(restored.tags, task.tags);
      expect(restored.subtasks.length, 2);
      expect(restored.subtasks[0].title, '子任务 A');
      expect(restored.subtasks[0].done, isTrue);
      expect(restored.subtasks[1].priority, TaskPriority.urgent);
      expect(restored.subtasks[1].tags, ['子标签']);
      expect(restored.subtasks[1].endTime, DateTime(2026, 9, 11, 20, 0));
      expect(restored.attachments.single.name, 'a.png');
      expect(restored.attachments.single.size, 12);
      expect(restored.comments.single.content, '备注');
    });

    test('枚举按名字序列化，不依赖序号', () {
      final json = TaskJson.taskToJson(buildTask());
      expect(json['status'], 'running');
      expect(json['type'], 'deadline');
      expect(json['priority'], 'high');
      expect(json['repeatType'], 'days');
    });

    test('未知枚举值回退到默认值，不会抛异常', () {
      final json = TaskJson.taskToJson(buildTask());
      json['status'] = 'somethingNew';
      json['priority'] = 42;
      final restored = TaskJson.taskFromJson(json)!;
      expect(restored.status, TaskStatus.running);
      expect(restored.priority, TaskPriority.normal);
    });

    test('缺少必要时间字段的脏数据被跳过', () {
      expect(TaskJson.taskFromJson({'uid': 'x'}), isNull);
      expect(TaskJson.taskFromJson({'startTime': '2026-01-01T00:00:00.000'}),
          isNull);
    });

    test('整包 encode / decode 往返一致', () {
      final bundle = bundleOf([
        buildTask()
      ], tombstones: [
        TaskTombstone(uid: 'gone', deletedAt: DateTime(2026, 9, 10, 18, 0)),
      ]);
      final decoded = DataBundle.decode(bundle.encode())!;

      expect(decoded.tasks.length, 1);
      expect(decoded.tasks.single.summary, '写给自己的一封信');
      expect(decoded.tombstones.single.uid, 'gone');
      expect(decoded.tags, ['学习', '紧急']);
      expect(decoded.tagColors['学习'], 0xFF007AFF);
      expect(decoded.reminderMode, 1);
      expect(decoded.alarmTheme, 'elysia');
    });

    test('不是本应用导出的文件返回 null', () {
      expect(DataBundle.decode('{"hello":1}'), isNull);
      expect(DataBundle.decode('not json at all'), isNull);
    });
  });

  group('合并', () {
    test('本地没有的待办会被加进来', () {
      final remote = buildTask(uid: 'new-1', summary: '远端新增');
      final result = DataMerge.merge(
        local: [],
        localTombstones: [],
        incoming: bundleOf([remote]),
      );
      expect(result.added, 1);
      expect(result.tasks.single.summary, '远端新增');
    });

    test('同 uid 时 updatedAt 新的胜出', () {
      final local = buildTask(
          uid: 'same', summary: '本地旧', updatedAt: DateTime(2026, 9, 10, 10, 0));
      final remote = buildTask(
          uid: 'same', summary: '远端新', updatedAt: DateTime(2026, 9, 10, 12, 0));

      final result = DataMerge.merge(
        local: [local],
        localTombstones: [],
        incoming: bundleOf([remote]),
      );
      expect(result.updated, 1);
      expect(result.tasks.single.summary, '远端新');
    });

    test('本地更新时不被远端旧数据覆盖', () {
      final local = buildTask(
          uid: 'same', summary: '本地新', updatedAt: DateTime(2026, 9, 10, 14, 0));
      final remote = buildTask(
          uid: 'same', summary: '远端旧', updatedAt: DateTime(2026, 9, 10, 12, 0));

      final result = DataMerge.merge(
        local: [local],
        localTombstones: [],
        incoming: bundleOf([remote]),
      );
      expect(result.updated, 0);
      expect(result.tasks.single.summary, '本地新');
    });

    test('墓碑能阻止被删除的待办复活', () {
      final deleted =
          buildTask(uid: 'killed', updatedAt: DateTime(2026, 9, 10, 10, 0));
      final result = DataMerge.merge(
        local: [],
        localTombstones: [
          TaskTombstone(uid: 'killed', deletedAt: DateTime(2026, 9, 10, 12, 0)),
        ],
        incoming: bundleOf([deleted]),
      );
      expect(result.tasks, isEmpty);
      expect(result.added, 0);
    });

    test('删除之后又被编辑过的待办会复活', () {
      final edited = buildTask(
          uid: 'killed',
          summary: '删后又改',
          updatedAt: DateTime(2026, 9, 10, 14, 0));
      final result = DataMerge.merge(
        local: [],
        localTombstones: [
          TaskTombstone(uid: 'killed', deletedAt: DateTime(2026, 9, 10, 12, 0)),
        ],
        incoming: bundleOf([edited]),
      );
      expect(result.tasks.single.summary, '删后又改');
    });

    test('墓碑作用于本地的待办（另一端删掉的会同步删掉）', () {
      final local =
          buildTask(uid: 'local-1', updatedAt: DateTime(2026, 9, 10, 10, 0));
      final result = DataMerge.merge(
        local: [local],
        localTombstones: [],
        incoming: bundleOf([], tombstones: [
          TaskTombstone(
              uid: 'local-1', deletedAt: DateTime(2026, 9, 10, 12, 0)),
        ]),
      );
      expect(result.tasks, isEmpty);
      expect(result.removed, 1);
      expect(result.tombstones.single.uid, 'local-1');
    });

    test('墓碑挂掉的日程，其《过去日程》副本也一并清掉', () {
      final legacy = buildTask(uid: 'legacy-1', type: TaskType.fixedlegacy);
      legacy.fromUid = 'parent-1';
      final result = DataMerge.merge(
        local: [legacy],
        localTombstones: [],
        incoming: bundleOf([], tombstones: [
          TaskTombstone(
              uid: 'parent-1', deletedAt: DateTime(2026, 9, 10, 12, 0)),
        ]),
      );
      expect(result.tasks, isEmpty);
    });

    test('两边新增的待办都会保留', () {
      final local = buildTask(uid: 'l', summary: '本地');
      final remote = buildTask(uid: 'r', summary: '远端');
      final result = DataMerge.merge(
        local: [local],
        localTombstones: [],
        incoming: bundleOf([remote]),
      );
      expect(result.tasks.length, 2);
      expect(result.added, 1);
    });

    test('重复合并同一份数据是幂等的', () {
      final local = buildTask(uid: 'same');
      final bundle = bundleOf([buildTask(uid: 'same')]);

      final first = DataMerge.merge(
          local: [local], localTombstones: [], incoming: bundle);
      final second = DataMerge.merge(
        local: first.tasks,
        localTombstones: first.tombstones,
        incoming: bundle,
      );

      expect(second.tasks.length, first.tasks.length);
      expect(second.added, 0);
      expect(second.updated, 0);
      expect(second.removed, 0);
    });
  });

  group('循环待办的下一次：两台各自生成的那份要合成一条（2026-09-30）', () {
    test('同来源 + 同到期时间 → 只留一条（就是用户看到的「两个洗头」）', () {
      final parent = buildTask(uid: 'parent-1');
      // 手机完成一次，生成了「下一次」（uid 是手机上随机生的）
      final phoneNext = buildTask(uid: 'next-phone')
        ..fromUid = 'parent-1'
        ..updatedAt = DateTime(2026, 9, 12, 9, 0);
      // 电脑也完成了一次，同样生成了「下一次」（uid 是电脑上随机生的）
      final desktopNext = buildTask(uid: 'next-desktop')
        ..fromUid = 'parent-1'
        ..updatedAt = DateTime(2026, 9, 12, 10, 0);

      final merged = DataMerge.merge(
        local: <Task>[parent, phoneNext],
        localTombstones: <TaskTombstone>[],
        incoming: bundleOf(<Task>[desktopNext]),
      );

      final fromParent = merged.tasks
          .where((task) => task.fromUid == 'parent-1')
          .toList();
      expect(fromParent.length, 1);
      // 留更晚改过的那条（与其它字段同一个口径）
      expect(fromParent.single.uid, 'next-desktop');
    });

    test('同来源但到期时间不同 → 是两次，都留着', () {
      final first = buildTask(uid: 'n1')..fromUid = 'parent-1';
      final second = buildTask(uid: 'n2')
        ..fromUid = 'parent-1'
        ..endTime = DateTime(2026, 10, 11, 22, 0);

      final merged = DataMerge.merge(
        local: <Task>[first],
        localTombstones: <TaskTombstone>[],
        incoming: bundleOf(<Task>[second]),
      );

      expect(merged.tasks.length, 2);
    });

    test('没有来源的普通待办不会被合并掉（同名也不合）', () {
      final a = buildTask(uid: 'x1', summary: '洗头');
      final b = buildTask(uid: 'x2', summary: '洗头');

      final merged = DataMerge.merge(
        local: <Task>[a],
        localTombstones: <TaskTombstone>[],
        incoming: bundleOf(<Task>[b]),
      );

      expect(merged.tasks.length, 2);
    });
  });
}
