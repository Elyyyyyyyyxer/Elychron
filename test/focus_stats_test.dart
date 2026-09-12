import 'package:celechron/model/focus_session.dart';
import 'package:celechron/model/focus_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// P4：专注统计的口径测试。
///
/// 口径先说清楚：**按会话的开始时间归档**，跨午夜的会话整段算在开始那天。
void main() {
  FocusSession session({
    required DateTime startedAt,
    required int focusedMinutes,
    String label = '敲代码',
    String? taskUid,
    int rounds = 1,
    bool completed = true,
  }) =>
      FocusSession(
        taskUid: taskUid,
        label: label,
        startedAt: startedAt,
        endedAt: startedAt.add(Duration(minutes: focusedMinutes)),
        focusedTime: Duration(minutes: focusedMinutes),
        rounds: rounds,
        completed: completed,
      );

  final now = DateTime(2026, 9, 12, 15, 30); // 周六

  group('区间合计', () {
    final sessions = [
      session(startedAt: DateTime(2026, 9, 12, 9, 0), focusedMinutes: 60),
      session(startedAt: DateTime(2026, 9, 12, 14, 0), focusedMinutes: 30),
      session(startedAt: DateTime(2026, 9, 11, 20, 0), focusedMinutes: 45),
      session(startedAt: DateTime(2026, 9, 5, 10, 0), focusedMinutes: 90),
    ];

    test('今天：只算今天的两条', () {
      expect(
        FocusStats.totalBetween(
            sessions, FocusStats.startOfToday(now), now.add(const Duration(days: 1))),
        const Duration(minutes: 90),
      );
    });

    test('本周：周一起算（9/12 是周六，本周从 9/7 开始）', () {
      final weekStart = FocusStats.startOfWeek(now);
      expect(weekStart, DateTime(2026, 9, 7));
      expect(
        FocusStats.totalBetween(sessions, weekStart, now.add(const Duration(days: 1))),
        const Duration(minutes: 135),
      );
    });

    test('本月：9/5 那条也算进来', () {
      expect(
        FocusStats.totalBetween(
            sessions, FocusStats.startOfMonth(now), now.add(const Duration(days: 1))),
        const Duration(minutes: 225),
      );
    });

    test('全部历史', () {
      expect(FocusStats.total(sessions), const Duration(minutes: 225));
    });

    test('只算时长大于 0 的会话（空会话不污染统计）', () {
      final withEmpty = [
        ...sessions,
        session(startedAt: DateTime(2026, 9, 12, 16, 0), focusedMinutes: 0),
      ];
      expect(FocusStats.total(withEmpty), const Duration(minutes: 225));
    });
  });

  group('每日合计（柱状图）', () {
    final sessions = [
      session(startedAt: DateTime(2026, 9, 10, 9, 0), focusedMinutes: 30),
      session(startedAt: DateTime(2026, 9, 10, 15, 0), focusedMinutes: 30),
      session(startedAt: DateTime(2026, 9, 12, 9, 0), focusedMinutes: 120, rounds: 2),
    ];

    test('连续七天，没有记录的天也在（值为 0）', () {
      final days = FocusStats.daily(sessions,
          fromDay: DateTime(2026, 9, 6), days: 7);
      expect(days.length, 7);
      expect(days.first.day, DateTime(2026, 9, 6));
      expect(days.first.focused, Duration.zero);
      expect(days[4].focused, const Duration(minutes: 60)); // 9/10
      expect(days[4].day, DateTime(2026, 9, 10));
      expect(days[6].focused, const Duration(minutes: 120)); // 9/12
      expect(days[6].rounds, 2);
    });
  });

  group('按专注对象聚合', () {
    final sessions = [
      session(startedAt: DateTime(2026, 9, 12, 9, 0), focusedMinutes: 60, label: '写报告', taskUid: 't1'),
      session(startedAt: DateTime(2026, 9, 12, 11, 0), focusedMinutes: 30, label: '写报告', taskUid: 't1'),
      session(startedAt: DateTime(2026, 9, 11, 9, 0), focusedMinutes: 45, label: '敲代码'),
      session(startedAt: DateTime(2026, 8, 1, 9, 0), focusedMinutes: 300, label: '旧记录'),
    ];

    test('同一任务的会话合并，按时长倒序', () {
      final list = FocusStats.byLabel(sessions);
      // 全部历史里「旧记录」300 分钟最长，其次才是合并后的「写报告」90 分钟
      expect(list.map((e) => e.label).toList(), ['旧记录', '写报告', '敲代码']);
      final report = list.firstWhere((e) => e.label == '写报告');
      expect(report.focused, const Duration(minutes: 90));
      expect(report.sessions, 2);
      expect(report.taskUid, 't1');
    });

    test('可以只看某个时间之后的', () {
      final list = FocusStats.byLabel(sessions, from: FocusStats.startOfMonth(now));
      expect(list.map((e) => e.label).toList(), ['写报告', '敲代码']);
      expect(list.first.focused, const Duration(minutes: 90));
    });

    test('自由专注按名字分开算', () {
      final list = FocusStats.byLabel([
        session(startedAt: DateTime(2026, 9, 12, 9, 0), focusedMinutes: 20, label: '看书'),
        session(startedAt: DateTime(2026, 9, 12, 10, 0), focusedMinutes: 40, label: '敲代码'),
      ]);
      expect(list.length, 2);
      expect(list.first.label, '敲代码');
    });
  });

  group('轮数与中断', () {
    test('轮数累加、中断数单独算', () {
      final sessions = [
        session(startedAt: DateTime(2026, 9, 12, 9, 0), focusedMinutes: 60, rounds: 1),
        session(
            startedAt: DateTime(2026, 9, 12, 11, 0),
            focusedMinutes: 20,
            rounds: 0,
            completed: false),
      ];
      expect(FocusStats.roundCount(sessions), 1);
      expect(FocusStats.interruptedCount(sessions), 1);
    });

    test('完整走完占比', () {
      final sessions = [
        session(startedAt: DateTime(2026, 9, 12, 9, 0), focusedMinutes: 60),
        session(startedAt: DateTime(2026, 9, 12, 10, 0), focusedMinutes: 60),
        session(
            startedAt: DateTime(2026, 9, 12, 11, 0),
            focusedMinutes: 30,
            completed: false),
        session(
            startedAt: DateTime(2026, 9, 12, 12, 0),
            focusedMinutes: 30,
            completed: false),
      ];
      expect(FocusStats.completionRate(sessions), 0.5);
    });

    test('没有会话时占比是 null（界面显示「还没数据」而不是 0%）', () {
      expect(FocusStats.completionRate(const []), isNull);
      expect(FocusStats.averageRound(const []), isNull);
    });

    test('平均每轮时长 = 总专注 / 总轮数', () {
      final sessions = [
        session(startedAt: DateTime(2026, 9, 12, 9, 0), focusedMinutes: 50, rounds: 1),
        session(startedAt: DateTime(2026, 9, 12, 11, 0), focusedMinutes: 70, rounds: 1),
      ];
      expect(FocusStats.averageRound(sessions), const Duration(minutes: 60));
    });
  });

  group('按标签聚合（一条会话计入它的每个标签）', () {
    final sessions = [
      session(
          startedAt: DateTime(2026, 9, 12, 9, 0),
          focusedMinutes: 60,
          label: '写报告',
          taskUid: 't1'),
      session(
          startedAt: DateTime(2026, 9, 12, 14, 0),
          focusedMinutes: 30,
          label: '看论文',
          taskUid: 't2'),
      // 放在八月：这样下面「只看某个月之后」那条能把它过滤掉
      session(startedAt: DateTime(2026, 8, 30, 9, 0), focusedMinutes: 45, label: '敲代码'),
    ];
    final tags = {
      't1': ['作业', '报告'],
      't2': ['论文'],
    };

    test('多标签的待办会重复计入，分项之和大于总时长（这是刻意的口径）', () {
      final list = FocusStats.byTag(sessions, tagsOfTask: tags);
      final byName = {for (final e in list) e.label: e.focused};
      expect(byName['作业'], const Duration(minutes: 60));
      expect(byName['报告'], const Duration(minutes: 60));
      expect(byName['论文'], const Duration(minutes: 30));
      expect(byName[FocusStats.untaggedLabel], const Duration(minutes: 45));
      // 分项之和 = 195 分钟 > 总时长 135 分钟
      final sum = list.fold(Duration.zero, (a, b) => a + b.focused);
      expect(sum > FocusStats.total(sessions), isTrue);
    });

    test('自由专注与没标签的待办都进「未打标签」，时长不丢', () {
      final list = FocusStats.byTag(
        [
          session(startedAt: DateTime(2026, 9, 12, 9, 0), focusedMinutes: 20),
          session(
              startedAt: DateTime(2026, 9, 12, 10, 0),
              focusedMinutes: 10,
              taskUid: 't3'),
        ],
        tagsOfTask: const {'t3': <String>[]},
      );
      expect(list.length, 1);
      expect(list.single.label, FocusStats.untaggedLabel);
      expect(list.single.focused, const Duration(minutes: 30));
      expect(list.single.sessions, 2);
    });

    test('可以只看某个月份之后的', () {
      final list = FocusStats.byTag(
        sessions,
        tagsOfTask: tags,
        from: FocusStats.startOfMonth(DateTime(2026, 9, 12)),
      );
      expect(list.any((e) => e.label == FocusStats.untaggedLabel), isFalse);
      expect(list.map((e) => e.label).toList(), ['作业', '报告', '论文']);
    });
  });
}
