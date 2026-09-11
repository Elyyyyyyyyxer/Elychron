import 'package:celechron/model/task.dart';
import 'package:celechron/mod/task_runtime_mod.dart' show normalizeLegacyTask;
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

  /// 单时刻任务（start 与 end 同一刻），用来测类型切换与时间状态行。
  Task moment(DateTime end) =>
      Task(endTime: end, startTime: end, repeatEndsTime: end);

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

  // ===== 本轮新增：显式切换类型 / 时间状态行 =====

  group('applyKind：显式切换类型时把时间字段摆对', () {
    test('切成活动：单时刻会被撑成 1 小时时段', () {
      final t = moment(DateTime(2026, 9, 11, 14, 0));
      t.applyKind(TaskType.fixed);
      expect(t.type, TaskType.fixed);
      expect(t.startTime, DateTime(2026, 9, 11, 13, 0));
      expect(t.endTime, DateTime(2026, 9, 11, 14, 0));
      expect(t.hasTimeRange, isTrue);
    });

    test('切成提醒：start 与 end 收成同一时刻，且默认打开提醒', () {
      final t = moment(DateTime(2026, 9, 11, 19, 50));
      t.startTime = DateTime(2026, 9, 11, 14, 20);
      t.applyKind(TaskType.remind);
      expect(t.startTime, t.endTime);
      expect(t.reminderEnabled, isTrue);
      expect(t.reminderTime, isNull);
      // reminderTime 为空就用锚点本身 —— 也就是「那一刻」
      expect(t.reminderTargetTime, t.endTime);
    });

    test('切成备忘：关掉提醒、清掉提醒时间', () {
      final t = moment(DateTime(2026, 9, 11, 19, 50));
      t.reminderEnabled = true;
      t.reminderTime = DateTime(2026, 9, 11, 19, 0);
      t.applyKind(TaskType.memo);
      expect(t.type, TaskType.memo);
      expect(t.reminderEnabled, isFalse);
      expect(t.reminderTime, isNull);
      expect(t.schedulesReminder, isFalse);
    });

    test('切成截止：start 与 end 收成同一时刻', () {
      final t = moment(DateTime(2026, 9, 11, 23, 59));
      t.startTime = DateTime(2026, 9, 11, 14, 0);
      t.applyKind(TaskType.deadline);
      expect(t.startTime, t.endTime);
      expect(t.endTimeLabel, '截止时间');
    });

    test('切换之后再 normalizeType 不会被翻回去', () {
      final t = moment(DateTime(2026, 9, 11, 23, 59));
      t.applyKind(TaskType.memo);
      t.normalizeType();
      expect(t.type, TaskType.memo);
    });

    test('各类型的时间行称呼', () {
      final t = moment(DateTime(2026, 9, 11, 23, 59));
      t.startTime = DateTime(2026, 9, 11, 22, 0);
      t.type = TaskType.fixed;
      expect(t.endTimeLabel, '结束时间');
      t.applyKind(TaskType.deadline);
      expect(t.endTimeLabel, '截止时间');
      t.applyKind(TaskType.remind);
      expect(t.endTimeLabel, '提醒时刻');
      t.applyKind(TaskType.memo);
      expect(t.endTimeLabel, '时间');
    });
  });

  group('timeStatus：哪一行、红不红', () {
    test('备忘不显示时间状态行', () {
      final t = moment(DateTime(2000, 1, 1));
      t.applyKind(TaskType.memo);
      expect(t.timeStatus, isNull);
    });

    test('截止过期才标红', () {
      final t = moment(DateTime.now().subtract(const Duration(hours: 2)));
      t.applyKind(TaskType.deadline);
      expect(t.timeStatus!.urgent, isTrue);
      expect(t.timeStatus!.text, startsWith('已超时'));
      expect(t.isOverdue, isTrue);
    });

    test('截止没过期不标红', () {
      final t = moment(DateTime.now().add(const Duration(hours: 2)));
      t.applyKind(TaskType.deadline);
      expect(t.timeStatus!.urgent, isFalse);
      expect(t.timeStatus!.text, startsWith('剩'));
    });

    test('提醒过期不标红（只是响过一次）', () {
      final t = moment(DateTime.now().subtract(const Duration(hours: 2)));
      t.applyKind(TaskType.remind);
      expect(t.timeStatus!.urgent, isFalse);
      expect(t.timeStatus!.text, startsWith('提醒已过'));
      expect(t.isOverdue, isFalse);
    });

    test('活动：未开始 / 进行中 / 已结束都不标红', () {
      final t = moment(DateTime.now().add(const Duration(hours: 3)));
      t.applyKind(TaskType.fixed);
      expect(t.timeStatus!.text, startsWith('距开始'));
      expect(t.timeStatus!.urgent, isFalse);

      t.startTime = DateTime.now().subtract(const Duration(minutes: 10));
      t.endTime = DateTime.now().add(const Duration(minutes: 50));
      expect(t.timeStatus!.text, '进行中');

      t.startTime = DateTime.now().subtract(const Duration(hours: 2));
      t.endTime = DateTime.now().subtract(const Duration(hours: 1));
      expect(t.timeStatus!.text, startsWith('已结束'));
      expect(t.timeStatus!.urgent, isFalse);
      expect(t.isOverdue, isFalse);
    });

    test('humanDuration 写成人话', () {
      expect(humanDuration(const Duration(seconds: 30)), '不到 1 分钟');
      expect(humanDuration(const Duration(minutes: 5)), '5 分钟');
      expect(humanDuration(const Duration(hours: 3, minutes: 20)), '3 小时 20 分钟');
      expect(humanDuration(const Duration(days: 2, hours: 3)), '2 天 3 小时');
    });
  });

  // ===== Step 5：活动结束后自动归档 =====

  group('needsAutoArchive：只有「不重复的活动结束了」才归档', () {
    Task endedEvent() {
      final t = moment(DateTime.now().subtract(const Duration(hours: 1)));
      t.applyKind(TaskType.fixed);
      t.startTime = DateTime.now().subtract(const Duration(hours: 3));
      t.endTime = DateTime.now().subtract(const Duration(hours: 1));
      return t;
    }

    test('不重复的活动结束之后就归档', () {
      expect(endedEvent().needsAutoArchive, isTrue);
    });

    test('活动还没结束不归档', () {
      final t = endedEvent();
      t.endTime = DateTime.now().add(const Duration(hours: 1));
      expect(t.needsAutoArchive, isFalse);
    });

    test('重复日程不归档（它会滚动到下一期）', () {
      final t = endedEvent();
      t.repeatType = TaskRepeatType.days;
      t.repeatPeriod = 7;
      expect(t.needsAutoArchive, isFalse);
    });

    test('已经打钩完成的不再动它', () {
      final t = endedEvent();
      t.status = TaskStatus.completed;
      expect(t.needsAutoArchive, isFalse);
    });

    test('内部《过去日程》不归档', () {
      final t = endedEvent();
      t.type = TaskType.fixedlegacy;
      expect(t.needsAutoArchive, isFalse);
    });

    test('截止过期仍留在「待我处理」，不归档', () {
      final t = moment(DateTime.now().subtract(const Duration(hours: 1)));
      t.applyKind(TaskType.deadline);
      expect(t.needsAutoArchive, isFalse);
    });

    test('提醒过期不归档（只是响过一次，随手划掉）', () {
      final t = moment(DateTime.now().subtract(const Duration(hours: 1)));
      t.applyKind(TaskType.remind);
      expect(t.needsAutoArchive, isFalse);
    });

    test('备忘永不过期，更不会归档', () {
      final t = moment(DateTime.now().subtract(const Duration(days: 3)));
      t.applyKind(TaskType.memo);
      expect(t.needsAutoArchive, isFalse);
    });
  });

  group('hasUnfinishedSubtasks：结束后点出没做完的步骤', () {
    Task endedEventWith({required int total, required int done}) {
      final t = moment(DateTime.now().subtract(const Duration(hours: 1)));
      t.applyKind(TaskType.fixed);
      t.startTime = DateTime.now().subtract(const Duration(hours: 3));
      t.endTime = DateTime.now().subtract(const Duration(hours: 1));
      for (var i = 0; i < total; i++) {
        t.subtasks.add(SubTask(title: '第 $i 步', done: i < done));
      }
      return t;
    }

    test('结束了还有没做完的 → 要提示', () {
      final t = endedEventWith(total: 3, done: 1);
      expect(t.hasUnfinishedSubtasks, isTrue);
      expect(t.subtasks.length - t.subtaskDoneCount, 2);
    });

    test('全做完了 → 不提示', () {
      expect(endedEventWith(total: 2, done: 2).hasUnfinishedSubtasks, isFalse);
    });

    test('还没结束 → 不提示', () {
      final t = endedEventWith(total: 2, done: 0);
      t.endTime = DateTime.now().add(const Duration(hours: 1));
      expect(t.hasUnfinishedSubtasks, isFalse);
    });

    test('没有子待办 → 不提示', () {
      expect(endedEventWith(total: 0, done: 0).hasUnfinishedSubtasks, isFalse);
    });
  });

  // ===== Step 8：老数据兼容 =====

  group('老数据：旧字段不会被新语义弄坏', () {
    test('早期版本把 DDL 写成「截止前 1 分钟」，仍会被抹平', () {
      final t = moment(DateTime(2026, 9, 11, 23, 59));
      t.startTime = DateTime(2026, 9, 11, 23, 58); // 老版本的脏数据
      expect(normalizeLegacyTask(t), isTrue);
      expect(t.startTime, t.endTime);
      expect(t.type, TaskType.deadline);
    });

    test('干净的老待办不会被改动（changed 必须是 false）', () {
      final t = moment(DateTime(2026, 9, 11, 23, 59));
      expect(normalizeLegacyTask(t), isFalse);
    });

    test('老的活动（日程）不会被当成待办抹平开始时间', () {
      final t = moment(DateTime(2026, 9, 12, 14, 10));
      t.type = TaskType.fixed;
      t.startTime = DateTime(2026, 9, 12, 13, 30);
      expect(normalizeLegacyTask(t), isFalse);
      expect(t.hasTimeRange, isTrue);
    });

    test('老数据的提醒锚点：活动从「结束」改锚「开始」（这是 P1 要修的错位）', () {
      final t = moment(DateTime(2026, 9, 12, 14, 10));
      t.type = TaskType.fixed;
      t.startTime = DateTime(2026, 9, 12, 13, 30);
      t.reminderEnabled = true;
      t.reminderTime = null; // 老数据常见：只开了开关、没存时刻
      expect(t.reminderAnchor, DateTime(2026, 9, 12, 13, 30));
    });

    test('老数据里没有 remind / memo —— 序号追加不影响已有三条', () {
      // 这是 Hive 按序号读写的关键保证：0/1/2 的含义永远不变
      expect(TaskType.values.length >= 5, isTrue);
      expect(TaskType.values[0], TaskType.deadline);
      expect(TaskType.values[1], TaskType.fixed);
      expect(TaskType.values[2], TaskType.fixedlegacy);
    });
  });
}
