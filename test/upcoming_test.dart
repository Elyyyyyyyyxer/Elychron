import 'package:celechron/model/period.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/upcoming.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「接下来」的排序/过滤逻辑测试。
///
/// 口径（用户定的）：课程/考试/日程按**开始时间**，非备忘待办按**提醒时间**，
/// 备忘永远不出现。
void main() {
  final now = DateTime(2026, 9, 12, 10, 0);

  Period period({
    required DateTime start,
    required DateTime end,
    String summary = '军事理论',
    String location = '教三 301',
    PeriodType type = PeriodType.classes,
    String description = '教师: 张老师\n课程代码: MIL1001\n教学时间安排: 秋冬 第1-2节',
  }) =>
      Period(
        uid: 'p-${start.toIso8601String()}',
        type: type,
        description: description,
        startTime: start,
        endTime: end,
        location: location,
        summary: summary,
      );

  Task task({
    String uid = 't1',
    String summary = '交实验报告',
    TaskType type = TaskType.deadline,
    DateTime? endTime,
    DateTime? reminderTime,
    String description = '',
    String location = '',
    TaskStatus status = TaskStatus.running,
  }) =>
      Task(
        uid: uid,
        summary: summary,
        description: description,
        location: location,
        endTime: endTime ?? DateTime(2026, 9, 20, 23, 59),
        startTime: endTime ?? DateTime(2026, 9, 20, 23, 59),
        repeatEndsTime: DateTime(2026, 9, 20),
      )
        ..type = type
        ..status = status
        ..reminderEnabled = true
        ..reminderTime = reminderTime;

  List<UpcomingItem> build({
    List<Period> periods = const [],
    List<Task> tasks = const [],
    Duration horizon = const Duration(days: 7),
    int limit = 8,
  }) =>
      buildUpcoming(
        periods: periods,
        tasks: tasks,
        now: now,
        horizon: horizon,
        limit: limit,
      );

  group('排序索引', () {
    test('课程按开始时间、待办按提醒时间，混在一起按时刻排', () {
      final items = build(
        periods: [
          period(
            start: DateTime(2026, 9, 12, 13, 30),
            end: DateTime(2026, 9, 12, 15, 5),
          ),
        ],
        tasks: [
          task(
            uid: 'a',
            summary: '交报告',
            endTime: DateTime(2026, 9, 12, 23, 0),
            reminderTime: DateTime(2026, 9, 12, 12, 0),
          ),
        ],
      );
      expect(items.length, 2);
      expect(items[0].title, '交报告'); // 12:00 早于 13:30
      expect(items[0].kind, UpcomingKind.deadline);
      expect(items[1].kind, UpcomingKind.course);
      expect(items[1].title, '军事理论');
    });

    test('提醒型：时刻就是提醒时间本身', () {
      final items = build(tasks: [
        task(
          summary: '取快递',
          type: TaskType.remind,
          endTime: DateTime(2026, 9, 12, 20, 15),
        ),
      ]);
      expect(items.single.kind, UpcomingKind.remind);
      expect(items.single.at, DateTime(2026, 9, 12, 20, 15));
    });

    test('活动型待办按开始时间排，带上结束时刻', () {
      final items = build(tasks: [
        task(
          summary: '班级团建',
          type: TaskType.fixed,
          endTime: DateTime(2026, 9, 13, 22, 0),
        ),
      ]);
      expect(items.single.kind, UpcomingKind.activity);
      expect(items.single.until, DateTime(2026, 9, 13, 22, 0));
    });
  });

  group('过滤', () {
    test('备忘永远不出现', () {
      final items = build(tasks: [
        task(summary: '买牙膏', type: TaskType.memo),
      ]);
      expect(items, isEmpty);
    });

    test('已完成 / 已删除的不出现', () {
      final items = build(tasks: [
        task(uid: 'a', status: TaskStatus.completed),
        task(uid: 'b', status: TaskStatus.deleted),
      ]);
      expect(items, isEmpty);
    });

    test('时间已经过去的（含提醒时间已过）不出现', () {
      final items = build(tasks: [
        task(
          summary: '早就该提醒了',
          endTime: DateTime(2026, 9, 12, 9, 0),
          reminderTime: DateTime(2026, 9, 12, 8, 30),
        ),
      ]);
      expect(items, isEmpty);
    });

    test('超出 7 天窗口的不出现', () {
      final items = build(tasks: [
        task(
          summary: '下周的事',
          endTime: DateTime(2026, 9, 25, 23, 0),
          reminderTime: DateTime(2026, 9, 25, 22, 0),
        ),
      ]);
      expect(items, isEmpty);
    });

    test('★ 进行中的课程保留（正在上课时不该只显示下一节）', () {
      final items = build(periods: [
        period(
          start: DateTime(2026, 9, 12, 8, 0),
          end: DateTime(2026, 9, 12, 11, 30),
        ),
        period(
          start: DateTime(2026, 9, 12, 13, 30),
          end: DateTime(2026, 9, 12, 15, 5),
          summary: '下午那节',
        ),
      ]);
      expect(items.first.title, '军事理论');
      expect(items.first.isRunningAt(now), isTrue);
    });

    test('已结束的课程不出现', () {
      final items = build(periods: [
        period(
          start: DateTime(2026, 9, 12, 8, 0),
          end: DateTime(2026, 9, 12, 9, 30),
        ),
      ]);
      expect(items, isEmpty);
    });

    test('虚拟占位块不出现', () {
      final items = build(periods: [
        period(
          start: DateTime(2026, 9, 12, 14, 0),
          end: DateTime(2026, 9, 12, 15, 0),
          type: PeriodType.virtual,
        ),
      ]);
      expect(items, isEmpty);
    });
  });

  group('限量与去重', () {
    test('最多 8 条', () {
      final items = build(
        periods: [
          for (var i = 0; i < 12; i++)
            period(
              start: DateTime(2026, 9, 12, 13, 0).add(Duration(days: i % 3, hours: i)),
              end: DateTime(2026, 9, 12, 14, 0).add(Duration(days: i % 3, hours: i)),
              summary: '第 $i 节',
            ),
        ],
      );
      expect(items.length, 8);
    });

    test('同一个 uid 只留一条', () {
      final shared = period(
        start: DateTime(2026, 9, 12, 14, 0),
        end: DateTime(2026, 9, 12, 15, 0),
      );
      final items = buildUpcoming(
        periods: [shared, shared.copyWith()],
        tasks: const [],
        now: now,
      );
      expect(items.length, 1);
    });
  });

  group('倒计时与时刻文案', () {
    test('进行中 / 马上开始 / 还有 X', () {
      final running = UpcomingItem(
        kind: UpcomingKind.course,
        at: DateTime(2026, 9, 12, 9, 30),
        until: DateTime(2026, 9, 12, 11, 0),
        title: '军事理论',
      );
      expect(upcomingCountdown(running, now), '进行中');

      final soon = UpcomingItem(
        kind: UpcomingKind.deadline,
        at: now.add(const Duration(seconds: 30)),
        title: '交报告',
      );
      expect(upcomingCountdown(soon, now), '马上开始');

      final later = UpcomingItem(
        kind: UpcomingKind.deadline,
        at: now.add(const Duration(hours: 3, minutes: 20)),
        title: '交报告',
      );
      expect(upcomingCountdown(later, now), '还有 3 小时 20 分');

      final tomorrow = UpcomingItem(
        kind: UpcomingKind.deadline,
        at: now.add(const Duration(days: 1, hours: 5)),
        title: '交报告',
      );
      expect(upcomingCountdown(tomorrow, now), '还有 1 天 5 小时');
    });

    test('时刻文案：今天 / 明天 / 后天 / 具体日期', () {
      UpcomingItem at(DateTime time) =>
          UpcomingItem(kind: UpcomingKind.course, at: time, title: 'x');
      expect(upcomingWhen(at(DateTime(2026, 9, 12, 14, 30)), now), '今天 14:30');
      expect(upcomingWhen(at(DateTime(2026, 9, 13, 8, 0)), now), '明天 08:00');
      expect(upcomingWhen(at(DateTime(2026, 9, 14, 8, 0)), now), '后天 08:00');
      expect(upcomingWhen(at(DateTime(2026, 9, 17, 13, 30)), now), '9 月 17 日 13:30');
    });
  });

  group('文案细节', () {
    test('课程备注丢掉「课程代码」那几行，留教师', () {
      final items = build(periods: [
        period(
          start: DateTime(2026, 9, 12, 14, 0),
          end: DateTime(2026, 9, 12, 15, 0),
        ),
      ]);
      expect(items.single.detail, '教师: 张老师');
      expect(items.single.location, '教三 301');
    });

    test('待办描述只取首行，太长就截断', () {
      final items = build(tasks: [
        task(
          description: '记得带身份证\n第二行不该出现',
          endTime: DateTime(2026, 9, 12, 20, 0),
          reminderTime: DateTime(2026, 9, 12, 19, 30),
        ),
      ]);
      expect(items.single.detail, '记得带身份证');
    });

    test('没有标题时给出兜底文案而不是空白', () {
      final items = build(tasks: [
        task(
          summary: '   ',
          endTime: DateTime(2026, 9, 12, 20, 0),
          reminderTime: DateTime(2026, 9, 12, 19, 30),
        ),
      ]);
      expect(items.single.title, '(未命名待办)');
    });
  });
}
