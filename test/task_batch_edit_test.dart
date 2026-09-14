import 'package:celechron/mod/task_batch_edit.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// 待办批量编辑的纯逻辑。
///
/// 三种批量操作（删除/完成/未完成）都要碰数据，没法在单测里跑；
/// 所以这里锁的是**规则**：谁能被完成、确认要合并成一次、选中集合怎么维护。
/// 这些规则一旦被改坏（比如"活动也能被标记完成"），用户会立刻感觉到不对。
void main() {
  Task make(
    String uid, {
    TaskType type = TaskType.deadline,
    TaskStatus status = TaskStatus.running,
    List<SubTask> subtasks = const [],
  }) {
    final now = DateTime.now();
    return Task(
      uid: uid,
      summary: '任务 $uid',
      endTime: now,
      startTime: now,
      repeatEndsTime: dateOnly(now),
      subtasks: subtasks,
    )
      ..type = type
      ..status = status;
  }

  setUp(() => TaskBatchEdit.exit());
  tearDown(() => TaskBatchEdit.exit());

  group('选中集合的维护', () {
    test('进入批量模式时清空选中', () {
      TaskBatchEdit.toggle(make('a'));
      expect(TaskBatchEdit.count, 1);
      TaskBatchEdit.enter();
      expect(TaskBatchEdit.count, 0);
      expect(TaskBatchEdit.active.value, isTrue);
    });

    test('退出批量模式会清空选中并关掉模式', () {
      TaskBatchEdit.enter();
      TaskBatchEdit.toggle(make('a'));
      TaskBatchEdit.exit();
      expect(TaskBatchEdit.count, 0);
      expect(TaskBatchEdit.active.value, isFalse);
    });

    test('再点一次 = 取消选中', () {
      final task = make('a');
      TaskBatchEdit.toggle(task);
      expect(TaskBatchEdit.isSelected(task), isTrue);
      TaskBatchEdit.toggle(task);
      expect(TaskBatchEdit.isSelected(task), isFalse);
    });

    test('resolve 只返回当前列表里还存在的选中项', () {
      TaskBatchEdit.toggle(make('a'));
      TaskBatchEdit.toggle(make('b'));
      final all = [make('a'), make('c')]; // b 已经被删掉了
      final resolved = TaskBatchEdit.resolve(all);
      expect(resolved.length, 1);
      expect(resolved.first.uid, 'a');
    });
  });

  group('谁能被"完成"', () {
    test('活动与日程不算完成，会被跳过并计数', () {
      final result = TaskBatchEdit.splitCompletable([
        make('deadline', type: TaskType.deadline),
        make('event', type: TaskType.fixed),
        make('legacy', type: TaskType.fixedlegacy),
        make('remind', type: TaskType.remind),
      ]);
      expect(result.completable.map((t) => t.uid).toList(),
          ['deadline', 'remind']);
      expect(result.skipped, 2);
    });

    test('全是活动时没有可完成的', () {
      final result = TaskBatchEdit.splitCompletable([
        make('e1', type: TaskType.fixed),
        make('e2', type: TaskType.fixed),
      ]);
      expect(result.completable, isEmpty);
      expect(result.skipped, 2);
    });
  });

  group('批量完成前的确认要合并成一次', () {
    test('只挑出"还有子待办没完成"的那些', () {
      final subtasks = [
        SubTask(uid: 's1', title: '第一步')..done = true,
        SubTask(uid: 's2', title: '第二步'),
      ];
      final allDone = [
        SubTask(uid: 's1', title: '第一步')..done = true,
      ];
      final result = TaskBatchEdit.withUnfinishedSubtasks([
        make('hasUnfinished', subtasks: subtasks),
        make('allDone', subtasks: allDone),
        make('noSubtasks'),
      ]);
      expect(result.map((t) => t.uid).toList(), ['hasUnfinished']);
    });

    test('一条都没有未完成子待办时不弹确认', () {
      expect(TaskBatchEdit.withUnfinishedSubtasks([make('a')]), isEmpty);
    });
  });
}
