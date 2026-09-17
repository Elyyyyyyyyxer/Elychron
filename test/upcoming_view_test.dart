import 'package:celechron/model/period.dart';
import 'package:celechron/model/upcoming.dart';
import 'package:celechron/page/calendar/upcoming_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 接下来页在**同时有好几件在进行中**时的样子与交互。
///
/// 口径（用户定 + 后来亲手纠正过）：
/// - 顶层只放一张大卡，点它是"看这条的信息"
/// - 其余进行中的条目**像一叠卡片那样重合**在下面（只露边，不写字）
/// - 点那叠边 → 弹出列表 → 在里面选一条放到顶层
///
/// 纯逻辑的切分另有 `upcoming_test.dart` 的单测；这里只测**画出来的样子与点击**。
void main() {
  final now = DateTime.now();

  UpcomingItem item({
    required String key,
    required UpcomingKind kind,
    required DateTime start,
    DateTime? end,
    required String title,
  }) =>
      UpcomingItem(
        kind: kind,
        at: start,
        until: end,
        title: title,
        period: Period(
          uid: key,
          type: switch (kind) {
            UpcomingKind.course => PeriodType.classes,
            UpcomingKind.exam => PeriodType.test,
            _ => PeriodType.user,
          },
          description: '',
          startTime: start,
          endTime: end ?? start,
          location: '',
          summary: title,
        ),
      );

  UpcomingItem course({String title = '专业课'}) => item(
        key: 'course',
        kind: UpcomingKind.course,
        start: now.subtract(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 1)),
        title: title,
      );

  UpcomingItem activity({String title = '组会', String key = 'meet'}) => item(
        key: key,
        kind: UpcomingKind.activity,
        start: now.subtract(const Duration(minutes: 30)),
        end: now.add(const Duration(hours: 1)),
        title: title,
      );

  UpcomingItem later({String title = '交实验报告'}) => item(
        key: 'later',
        kind: UpcomingKind.deadline,
        start: now.add(const Duration(hours: 3)),
        title: title,
      );

  final stack = find.byKey(const ValueKey('running-stack'));

  Future<void> pump(WidgetTester tester, List<UpcomingItem> items) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(child: UpcomingView(items: items)),
      ),
    );
  }

  /// 点那叠卡边 → 弹出列表
  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(stack);
    await tester.pumpAndSettle();
  }

  testWidgets('只有一件进行中：下面没有那叠卡边', (tester) async {
    await pump(tester, [course(), later()]);
    expect(stack, findsNothing);
    expect(find.text('专业课'), findsOneWidget);
    expect(find.text('之后还有'), findsOneWidget);
  });

  testWidgets('★ 两件进行中：顶层一张大卡 + 下面露出卡边（不列标题）', (tester) async {
    await pump(tester, [course(), activity(), later()]);
    // 顶层是课程优先
    expect(find.text('专业课'), findsOneWidget);
    // 另一件只作为"卡边"存在，**不**把标题摆在页面上
    expect(stack, findsOneWidget);
    expect(find.text('组会'), findsNothing);
    // 也不该再出现旧版那行文字
    expect(find.textContaining('同时还有'), findsNothing);
  });

  testWidgets('★ 点那叠卡边 → 弹出全部进行中的列表（顶层标着"当前"）', (tester) async {
    await pump(tester, [course(), activity()]);
    await openPicker(tester);
    expect(find.text('同时进行中'), findsOneWidget);
    expect(find.text('专业课'), findsWidgets);
    expect(find.text('组会'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
  });

  testWidgets('★ 在列表里选一条 → 它换到顶层，原来那张落回卡边', (tester) async {
    await pump(tester, [course(), activity()]);
    await openPicker(tester);
    await tester.tap(find.byKey(const ValueKey('running-pick-period:meet')));
    await tester.pumpAndSettle();

    // 列表关掉，组会变成顶层大卡；专业课退成卡边（标题不再出现在页面上）
    expect(find.text('同时进行中'), findsNothing);
    expect(find.text('组会'), findsOneWidget);
    expect(find.text('专业课'), findsNothing);
    expect(stack, findsOneWidget);
  });

  testWidgets('三件进行中：列表里三条都在', (tester) async {
    await pump(tester, [
      course(),
      activity(),
      activity(title: '实验室例会', key: 'lab'),
    ]);
    await openPicker(tester);
    expect(find.text('专业课'), findsWidgets);
    expect(find.text('组会'), findsOneWidget);
    expect(find.text('实验室例会'), findsOneWidget);
  });

  testWidgets('点错了能点回来（换上去的那张也会退成卡边）', (tester) async {
    await pump(tester, [course(), activity()]);
    await openPicker(tester);
    await tester.tap(find.byKey(const ValueKey('running-pick-period:meet')));
    await tester.pumpAndSettle();
    expect(find.text('组会'), findsOneWidget);

    await openPicker(tester);
    await tester.tap(find.byKey(const ValueKey('running-pick-period:course')));
    await tester.pumpAndSettle();
    expect(find.text('专业课'), findsOneWidget);
    expect(find.text('组会'), findsNothing);
  });

  testWidgets('★ 手机宽度下不溢出（默认测试画布 800 宽比手机宽，靠这条兜住）', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pump(tester, [
      course(title: '习近平新时代中国特色社会主义思想概论'),
      activity(title: '实验室组会与项目进展汇报（每周例会）'),
    ]);
    expect(stack, findsOneWidget);
    await openPicker(tester);
    expect(find.text('同时进行中'), findsOneWidget);
  });
}
