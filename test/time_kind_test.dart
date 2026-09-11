import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// P1「四种时间语义」的数据层测试。
///
/// 这四类全部由 `TaskType` 映射得到，不新增存储字段（Hive 按序号存，
/// 只允许往后追加枚举值）。这里把映射规则、提醒锚点、逾期与日历可见性钉住，
/// 因为后面所有界面与提醒调度都依赖它们。
void main() {
  Task makeTask({required TaskType type}) {
    final start = DateTime(2026, 9, 11, 14, 20);
    final end = DateTime(2026, 9, 11, 19, 50);
    final task = Task(
      summary: '班级团建',
      endTime:
          type == TaskType.fixed || type == TaskType.fixedlegacy ? end : start,
      startTime: start,
      repeatEndsTime: end,
    );
    task.type = type;
    return task;
  }

  group('类型映射', () {
    test('活动：有起止，isEvent 为真，提醒锚点是开始时间', () {
      final t = makeTask(type: TaskType.fixed);
      expect(t.isEvent, isTrue);
      expect(t.isMemo, isFalse);
      expect(t.isRemind, isFalse);
      expect(t.reminderAnchor, DateTime(2026, 9, 11, 14, 20));
    });

    test('fixedlegacy（内部《过去日程》）同样按活动处理', () {
      final t = makeTask(type: TaskType.fixedlegacy);
      expect(t.isEvent, isTrue);
      expect(t.reminderAnchor, DateTime(2026, 9, 11, 14, 20));
    });

    test('截止：提醒锚点是截止时间', () {
      final t = makeTask(type: TaskType.deadline);
      expect(t.isEvent, isFalse);
      expect(t.reminderAnchor, t.endTime);
    });

    test('提醒：提醒锚点就是那一刻', () {
      final t = makeTask(type: TaskType.remind);
      expect(t.isRemind, isTrue);
      expect(t.reminderAnchor, t.endTime);
    });

    test('备忘：不提醒、不逾期、不进日历', () {
      final t = makeTask(type: TaskType.memo);
      t.reminderEnabled = true; // 即便被设过，也不允许调度
      expect(t.isMemo, isTrue);
      expect(t.schedulesReminder, isFalse);
      expect(t.isOverdue, isFalse);
      expect(t.showsInCalendar, isFalse);
    });
  });

  group('提醒调度判定', () {
    test('未开启提醒时不调度', () {
      final t = makeTask(type: TaskType.fixed);
      t.reminderEnabled = false;
      expect(t.schedulesReminder, isFalse);
    });

    test('活动开启提醒时按开始时间调度', () {
      final t = makeTask(type: TaskType.fixed);
      t.reminderEnabled = true;
      expect(t.schedulesReminder, isTrue);
      expect(t.reminderTargetTime, DateTime(2026, 9, 11, 14, 20));
    });

    test('显式设过 reminderTime 时以它为准（提前量已算在里面）', () {
      final t = makeTask(type: TaskType.fixed);
      t.reminderEnabled = true;
      t.reminderTime = DateTime(2026, 9, 11, 13, 50);
      expect(t.reminderTargetTime, DateTime(2026, 9, 11, 13, 50));
    });
  });

  group('normalizeType 不覆盖显式选择', () {
    test('活动与截止之间仍会按起止时间推断', () {
      final t = makeTask(type: TaskType.deadline);
      t.type = TaskType.fixed; // 先给个错的
      t.startTime = DateTime(2026, 9, 11, 9, 0);
      t.endTime = DateTime(2026, 9, 11, 10, 0);
      t.normalizeType();
      expect(t.type, TaskType.fixed);
    });

    test('提醒型不会被翻转成截止', () {
      final t = makeTask(type: TaskType.remind);
      t.startTime = t.endTime; // 单时刻
      t.normalizeType();
      expect(t.type, TaskType.remind);
    });

    test('备忘型不会被翻转成截止', () {
      final t = makeTask(type: TaskType.memo);
      t.startTime = t.endTime;
      t.normalizeType();
      expect(t.type, TaskType.memo);
    });
  });

  group('枚举序号必须稳定（Hive 兼容）', () {
    test('已有值序号不变，新值追加在后面', () {
      expect(TaskType.deadline.index, 0);
      expect(TaskType.fixed.index, 1);
      expect(TaskType.fixedlegacy.index, 2);
      expect(TaskType.remind.index, 3);
      expect(TaskType.memo.index, 4);
    });
  });
}
