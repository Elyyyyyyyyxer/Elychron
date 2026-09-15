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

  // ===== 「同时有好几件在进行中」：顶层 / 折叠堆 / 之后还有 三段划分 =====
  //
  // 用户遇到的实际情况：同一时刻有两件事在进行（比如上课 + 一个日程），
  // 页面上却只有一条看得出「进行中」。这里把口径钉死。
  group('多个进行中', () {
    /// 直接造条目 —— 只测切分口径，不掺 buildUpcoming 的过滤规则
    UpcomingItem item({
      required String key,
      required UpcomingKind kind,
      required DateTime start,
      DateTime? end,
      String? title,
    }) =>
        UpcomingItem(
          kind: kind,
          at: start,
          until: end,
          title: title ?? key,
          period: Period(
            uid: key,
            type: switch (kind) {
              UpcomingKind.course => PeriodType.classes,
              UpcomingKind.exam => PeriodType.test,
              UpcomingKind.activity => PeriodType.user,
              _ => PeriodType.user,
            },
            description: '',
            startTime: start,
            endTime: end ?? start,
            location: '',
            summary: title ?? key,
          ),
        );

    test('buildUpcoming 会把两件进行中的都留下（原来第二条只能掉进「之后还有」）', () {
      final items = build(periods: [
        period(
          start: DateTime(2026, 9, 12, 8, 0),
          end: DateTime(2026, 9, 12, 11, 30),
          summary: '专业课',
        ),
        period(
          start: DateTime(2026, 9, 12, 9, 30),
          end: DateTime(2026, 9, 12, 11, 0),
          summary: '组会',
          type: PeriodType.user,
        ),
        period(
          start: DateTime(2026, 9, 12, 13, 30),
          end: DateTime(2026, 9, 12, 15, 5),
          summary: '下午那节',
        ),
      ]);
      expect(runningUpcoming(items, now).length, 2);
      expect(
        runningUpcoming(items, now).map((e) => e.title),
        ['专业课', '组会'],
      );
    });

    test('没有进行中的：顶层就是最近那条，其余进「之后还有」', () {
      final items = [
        item(
          key: 'a',
          kind: UpcomingKind.deadline,
          start: DateTime(2026, 9, 12, 12, 0),
        ),
        item(
          key: 'b',
          kind: UpcomingKind.course,
          start: DateTime(2026, 9, 12, 13, 30),
        ),
      ];
      final layout = layoutUpcoming(items, now)!;
      expect(layout.headIsRunning, isFalse);
      expect(layout.head.title, 'a');
      expect(layout.otherRunning, isEmpty);
      expect(layout.later.map((e) => e.title), ['b']);
    });

    test('空列表给出 null（界面据此走空状态）', () {
      expect(layoutUpcoming(const [], now), isNull);
    });

    test('★ 两件进行中：顶层默认课程优先，另一件折叠起来', () {
      // 组会 09:30 开始得更早，但顶层仍应是 08:00 开始的专业课
      final items = [
        item(
          key: 'course',
          kind: UpcomingKind.course,
          start: DateTime(2026, 9, 12, 8, 0),
          end: DateTime(2026, 9, 12, 11, 30),
          title: '专业课',
        ),
        item(
          key: 'meet',
          kind: UpcomingKind.activity,
          start: DateTime(2026, 9, 12, 9, 30),
          end: DateTime(2026, 9, 12, 11, 0),
          title: '组会',
        ),
        item(
          key: 'later',
          kind: UpcomingKind.deadline,
          start: DateTime(2026, 9, 12, 12, 0),
        ),
      ];
      final layout = layoutUpcoming(items, now)!;
      expect(layout.headIsRunning, isTrue);
      expect(layout.head.title, '专业课');
      expect(layout.topIndex, 0);
      expect(layout.otherRunning.map((e) => e.title), ['组会']);
      // 进行中的不能同时出现在「之后还有」里（否则同一条会显示两遍）
      expect(layout.later.map((e) => e.title), ['later']);
    });

    test('两件进行中且都不是课程：按开始时间最早的当顶层', () {
      final items = [
        item(
          key: 'exam',
          kind: UpcomingKind.exam,
          start: DateTime(2026, 9, 12, 7, 30),
          end: DateTime(2026, 9, 12, 11, 0),
          title: '期中考试',
        ),
        item(
          key: 'meet',
          kind: UpcomingKind.activity,
          start: DateTime(2026, 9, 12, 9, 30),
          end: DateTime(2026, 9, 12, 11, 0),
          title: '组会',
        ),
      ];
      final layout = layoutUpcoming(items, now)!;
      expect(layout.head.title, '期中考试');
      expect(layout.otherRunning.map((e) => e.title), ['组会']);
    });

    test('两门课撞在同一节：都进行中，顶层是开始更早的那门，另一门折叠', () {
      final items = [
        item(
          key: 'c1',
          kind: UpcomingKind.course,
          start: DateTime(2026, 9, 12, 8, 0),
          end: DateTime(2026, 9, 12, 11, 30),
          title: '数据结构',
        ),
        item(
          key: 'c2',
          kind: UpcomingKind.course,
          start: DateTime(2026, 9, 12, 9, 50),
          end: DateTime(2026, 9, 12, 11, 30),
          title: '能源工程伦理',
        ),
      ];
      final layout = layoutUpcoming(items, now)!;
      expect(layout.head.title, '数据结构');
      expect(layout.otherRunning.map((e) => e.title), ['能源工程伦理']);
    });

    test('★ 点折叠里的那条可以换到顶层，原来那张落回折叠堆', () {
      final meeting = item(
        key: 'meet',
        kind: UpcomingKind.activity,
        start: DateTime(2026, 9, 12, 9, 30),
        end: DateTime(2026, 9, 12, 11, 0),
        title: '组会',
      );
      final items = [
        item(
          key: 'course',
          kind: UpcomingKind.course,
          start: DateTime(2026, 9, 12, 8, 0),
          end: DateTime(2026, 9, 12, 11, 30),
          title: '专业课',
        ),
        meeting,
      ];
      final pinned =
          layoutUpcoming(items, now, pinnedKey: meeting.dedupeKey)!;
      expect(pinned.head.title, '组会');
      expect(pinned.topIndex, 1);
      expect(pinned.otherRunning.map((e) => e.title), ['专业课']);
    });

    test('置顶的那条已经结束了 → 回到默认口径（不会一直挡着课程）', () {
      final items = [
        item(
          key: 'course',
          kind: UpcomingKind.course,
          start: DateTime(2026, 9, 12, 8, 0),
          end: DateTime(2026, 9, 12, 11, 30),
          title: '专业课',
        ),
      ];
      final layout = layoutUpcoming(items, now, pinnedKey: '走掉了')!;
      expect(layout.head.title, '专业课');
      expect(layout.topIndex, defaultTopRunningIndex(layout.running));
    });

    test('只有一件进行中：折叠堆是空的（就不会显示「同时还有」那行）', () {
      final items = [
        item(
          key: 'course',
          kind: UpcomingKind.course,
          start: DateTime(2026, 9, 12, 8, 0),
          end: DateTime(2026, 9, 12, 11, 30),
          title: '专业课',
        ),
        item(
          key: 'later',
          kind: UpcomingKind.deadline,
          start: DateTime(2026, 9, 12, 14, 0),
        ),
      ];
      final layout = layoutUpcoming(items, now)!;
      expect(layout.head.title, '专业课');
      expect(layout.otherRunning, isEmpty);
      expect(layout.later.map((e) => e.title), ['later']);
    });
  });
}
