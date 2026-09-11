import 'package:celechron/mod/ai/ai_task_draft.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// P1：AI 划分「四种时间语义」的校验测试。
///
/// 模型可以胡说，但它说的每一个枚举值都要在 `_fromJson` 里过一遍白名单与
/// 一致性检查。这里把那条边界钉住：**模型给的类型只当建议，最终以校验结果为准**，
/// 而且每次替用户改过什么都不许静默 —— 必须留一条 warnings。
void main() {
  /// 一个最小可用的模型输出
  Map<String, dynamic> base({
    String? kind,
    String? startTime,
    String? endTime,
    Object? reminderMinutes,
    String summary = '参加面试',
  }) =>
      <String, dynamic>{
        'summary': summary,
        if (kind != null) 'kind': kind,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        if (reminderMinutes != null) 'reminderMinutes': reminderMinutes,
      };

  /// applyTo 要往一条真实待办上写，给它一个干净的空壳
  Task emptyTask() {
    final now = DateTime.now();
    return Task(endTime: now, startTime: now, repeatEndsTime: now);
  }

  /// 相对今天的时间字符串（避免测试因日期而飘）
  String at({required int days, required int hour, int minute = 0}) {
    final d = DateTime.now().add(Duration(days: days));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}T${two(hour)}:${two(minute)}:00';
  }

  group('kind 白名单', () {
    test('中文四种写法都认', () {
      expect(
          AiTaskDraft.fromJsonForTest(base(
            kind: '活动',
            startTime: at(days: 1, hour: 14),
            endTime: at(days: 1, hour: 16),
          )).kind,
          TaskType.fixed);
      expect(
          AiTaskDraft.fromJsonForTest(base(kind: '截止', endTime: at(days: 1, hour: 23, minute: 59)))
              .kind,
          TaskType.deadline);
      expect(
          AiTaskDraft.fromJsonForTest(base(kind: '提醒', endTime: at(days: 1, hour: 9))).kind,
          TaskType.remind);
      expect(AiTaskDraft.fromJsonForTest(base(kind: '备忘')).kind, TaskType.memo);
    });

    test('英文别名也认', () {
      expect(
          AiTaskDraft.fromJsonForTest(base(
            kind: 'event',
            startTime: at(days: 1, hour: 14),
            endTime: at(days: 1, hour: 16),
          )).kind,
          TaskType.fixed);
      expect(AiTaskDraft.fromJsonForTest(base(kind: 'memo')).kind, TaskType.memo);
      expect(
          AiTaskDraft.fromJsonForTest(base(kind: 'remind', endTime: at(days: 1, hour: 9))).kind,
          TaskType.remind);
      expect(
          AiTaskDraft.fromJsonForTest(base(kind: 'DDL', endTime: at(days: 1, hour: 9))).kind,
          TaskType.deadline);
    });

    test('不认识的写法：退回按时间推断，并留一条提醒', () {
      final draft = AiTaskDraft.fromJsonForTest(base(
        kind: '很重要',
        startTime: at(days: 1, hour: 14),
        endTime: at(days: 1, hour: 16),
      ));
      expect(draft.kind, TaskType.fixed); // 有开始时间 → 活动
      expect(draft.warnings.any((w) => w.contains('时间类型')), isTrue);
    });

    test('模型没给 kind：有开始时间算活动，没有算截止', () {
      expect(
          AiTaskDraft.fromJsonForTest(base(
            startTime: at(days: 1, hour: 14),
            endTime: at(days: 1, hour: 16),
          )).kind,
          TaskType.fixed);
      expect(AiTaskDraft.fromJsonForTest(base(endTime: at(days: 1, hour: 23, minute: 59))).kind,
          TaskType.deadline);
    });

    test('内部值 fixedlegacy 绝不放进来', () {
      final draft = AiTaskDraft.fromJsonForTest(base(
        kind: 'fixedlegacy',
        endTime: at(days: 1, hour: 9),
      ));
      expect(draft.kind, isNot(TaskType.fixedlegacy));
    });
  });

  group('一致性校验：以 kind 为准，改动必须留痕', () {
    test('说要建活动却没给开始时间 → 降级成截止', () {
      final draft = AiTaskDraft.fromJsonForTest(base(
        kind: '活动',
        endTime: at(days: 1, hour: 16),
      ));
      expect(draft.kind, TaskType.deadline);
      expect(draft.startTime, isNull);
      expect(draft.warnings.any((w) => w.contains('已按「截止」处理')), isTrue);
    });

    test('活动的开始时间不早于结束时间 → 那其实不是时段，同样降级成截止', () {
      final draft = AiTaskDraft.fromJsonForTest(base(
        kind: '活动',
        startTime: at(days: 1, hour: 16),
        endTime: at(days: 1, hour: 16),
      ));
      expect(draft.startTime, isNull);
      expect(draft.kind, TaskType.deadline);
      // _validateStartTime 已经解释过为什么丢掉开始时间，加上我们那条降级说明
      expect(draft.warnings.any((w) => w.contains('不早于结束时间')), isTrue);
      expect(draft.warnings.any((w) => w.contains('已按「截止」处理')), isTrue);
    });

    test('截止/提醒型被塞了开始时间 → 丢掉，并留一条', () {
      final deadlineDraft = AiTaskDraft.fromJsonForTest(base(
        kind: '截止',
        startTime: at(days: 1, hour: 14),
        endTime: at(days: 1, hour: 23, minute: 59),
      ));
      expect(deadlineDraft.startTime, isNull);
      expect(deadlineDraft.warnings.any((w) => w.contains('不需要开始时间')), isTrue);

      final remindDraft = AiTaskDraft.fromJsonForTest(base(
        kind: '提醒',
        startTime: at(days: 1, hour: 9),
        endTime: at(days: 1, hour: 9),
      ));
      expect(remindDraft.startTime, isNull);
    });
  });

  group('提醒提前量', () {
    test('活动与截止接受模型给的提前量', () {
      final draft = AiTaskDraft.fromJsonForTest(base(
        kind: '活动',
        startTime: at(days: 1, hour: 14),
        endTime: at(days: 1, hour: 16),
        reminderMinutes: 30,
      ));
      expect(draft.reminderMinutes, 30);
    });

    test('提醒型就是那一刻，模型的提前量被忽略', () {
      final draft = AiTaskDraft.fromJsonForTest(base(
        kind: '提醒',
        endTime: at(days: 1, hour: 9),
        reminderMinutes: 120,
      ));
      expect(draft.reminderMinutes, 0);
    });

    test('备忘型从不提醒', () {
      final draft = AiTaskDraft.fromJsonForTest(base(
        kind: '备忘',
        reminderMinutes: 60,
      ));
      expect(draft.kind, TaskType.memo);
      expect(draft.reminderMinutes, 0);
    });
  });

  group('备忘型的时间占位', () {
    test('完全没有时间也不报错、不写 warning', () {
      final draft = AiTaskDraft.fromJsonForTest(base(kind: '备忘', summary: '买牙膏'));
      expect(draft.kind, TaskType.memo);
      final now = DateTime.now();
      expect(draft.endTime,
          DateTime(now.year, now.month, now.day, 23, 59));
      expect(draft.warnings.where((w) => w.contains('时间')).isEmpty, isTrue);
    });
  });

  group('applyTo：把类型真的落到待办上', () {
    test('活动：撑出时段，提醒锚开始时间', () {
      final draft = AiTaskDraft.fromJsonForTest(base(
        kind: '活动',
        startTime: at(days: 1, hour: 14),
        endTime: at(days: 1, hour: 16),
        reminderMinutes: 30,
      ));
      final task = emptyTask();
      draft.applyTo(task);
      expect(task.type, TaskType.fixed);
      expect(task.hasTimeRange, isTrue);
      expect(task.reminderAnchor, task.startTime);
      expect(task.reminderEnabled, isTrue);
      expect(task.reminderTargetTime, task.startTime.subtract(const Duration(minutes: 30)));
    });

    test('提醒：到点响，不提前', () {
      final draft = AiTaskDraft.fromJsonForTest(base(
        kind: '提醒',
        endTime: at(days: 1, hour: 9),
      ));
      final task = emptyTask();
      draft.applyTo(task);
      expect(task.type, TaskType.remind);
      expect(task.startTime, task.endTime);
      expect(task.reminderEnabled, isTrue);
      expect(task.reminderTargetTime, task.endTime);
      expect(task.schedulesReminder, isTrue);
    });

    test('备忘：不提醒、不逾期、不进日历', () {
      final draft = AiTaskDraft.fromJsonForTest(base(kind: '备忘', summary: '买牙膏'));
      final task = emptyTask();
      draft.applyTo(task);
      expect(task.type, TaskType.memo);
      expect(task.reminderEnabled, isFalse);
      expect(task.schedulesReminder, isFalse);
      expect(task.isOverdue, isFalse);
      expect(task.showsInCalendar, isFalse);
      expect(task.timeStatus, isNull);
    });

    test('截止：过期才标红', () {
      final draft = AiTaskDraft.fromJsonForTest(base(
        kind: '截止',
        endTime: at(days: 2, hour: 23, minute: 59),
      ));
      final task = emptyTask();
      draft.applyTo(task);
      expect(task.type, TaskType.deadline);
      expect(task.isOverdue, isFalse);
      expect(task.timeStatus!.urgent, isFalse);
    });
  });
}
