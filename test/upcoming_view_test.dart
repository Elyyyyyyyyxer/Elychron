import 'package:celechron/model/period.dart';
import 'package:celechron/model/upcoming.dart';
import 'package:celechron/page/calendar/upcoming_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「接下来」页在**同时有好几件在进行中**时的观感测试。
///
/// 用户外出、手机断连，真机验证暂时做不了 —— 这里用 widget 测试把三件事钉住：
/// 顶层默认课程优先、折叠堆写明数量、点一下能换到顶层。
///
/// （纯逻辑的切分口径另有 `upcoming_test.dart` 的 9 条单测；这里只测**画出来的样子**。）
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

  /// 一件正在进行的课程（08:00 开始，还要上一小时）
  UpcomingItem course({String title = '专业课'}) => item(
        key: 'course',
        kind: UpcomingKind.course,
        start: now.subtract(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 1)),
        title: title,
      );

  /// 一件正在进行的日程（半小时前开始）
  UpcomingItem activity({String title = '组会', String key = 'meet'}) => item(
        key: key,
        kind: UpcomingKind.activity,
        start: now.subtract(const Duration(minutes: 30)),
        end: now.add(const Duration(hours: 1)),
        title: title,
      );

  /// 一件还没开始的（进「之后还有」）
  UpcomingItem later({String title = '交实验报告'}) => item(
        key: 'later',
        kind: UpcomingKind.deadline,
        start: now.add(const Duration(hours: 3)),
        title: title,
      );

  Future<void> pump(WidgetTester tester, List<UpcomingItem> items) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(child: UpcomingView(items: items)),
      ),
    );
  }

  /// `RoundRectangleCard` 的点击是"抬手 125ms 后才真正回调"（它自己那套缩放动画），
  /// 所以点完还得把时钟往前推一下。
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('只有一件进行中：不出现「同时还有」那一行', (tester) async {
    await pump(tester, [course(), later()]);
    expect(find.textContaining('同时还有'), findsNothing);
    expect(find.text('专业课'), findsOneWidget);
    expect(find.text('之后还有'), findsOneWidget);
  });

  testWidgets('★ 两件进行中：顶层是课程，另一件折叠在下面并写明数量', (tester) async {
    await pump(tester, [course(), activity(), later()]);
    expect(find.textContaining('同时还有 1 个进行中'), findsOneWidget);
    // 两件都在页面上：一件是顶层大卡，一件是折叠的小卡
    expect(find.text('专业课'), findsOneWidget);
    expect(find.text('组会'), findsOneWidget);
    // 顶层在上：专业课的纵坐标更小
    expect(
      tester.getCenter(find.text('专业课')).dy <
          tester.getCenter(find.text('组会')).dy,
      isTrue,
    );
  });

  testWidgets('★ 点折叠里那条 → 它换到顶层，原来那张落回折叠堆', (tester) async {
    await pump(tester, [course(), activity()]);
    // 换之前：专业课在上
    expect(
      tester.getCenter(find.text('专业课')).dy <
          tester.getCenter(find.text('组会')).dy,
      isTrue,
    );

    await tapAndSettle(tester, find.text('组会'));

    // 换之后：组会跑到上面去了，专业课成了折叠的那张
    expect(
      tester.getCenter(find.text('组会')).dy <
          tester.getCenter(find.text('专业课')).dy,
      isTrue,
    );
    expect(find.textContaining('同时还有 1 个进行中'), findsOneWidget);
  });

  testWidgets('三件进行中：数量写 2，两张折叠卡都在', (tester) async {
    await pump(tester, [
      course(),
      activity(),
      activity(title: '实验室例会', key: 'lab'),
    ]);
    expect(find.textContaining('同时还有 2 个进行中'), findsOneWidget);
    expect(find.text('组会'), findsOneWidget);
    expect(find.text('实验室例会'), findsOneWidget);
  });

  testWidgets('点错了能点回来（换上去的那张也会落进折叠堆）', (tester) async {
    await pump(tester, [course(), activity()]);
    await tapAndSettle(tester, find.text('组会'));
    // 现在专业课在折叠堆里，点它换回来
    await tapAndSettle(tester, find.text('专业课'));
    expect(
      tester.getCenter(find.text('专业课')).dy <
          tester.getCenter(find.text('组会')).dy,
      isTrue,
    );
  });

  testWidgets('★ 手机宽度下不溢出（默认测试画布 800 宽比手机宽，靠这条兜住）', (tester) async {
    // 常见手机逻辑宽度 360；标题故意给长的，逼出省略号那条分支
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
    // 只要画出来不报 overflow，就说明标题与那排小字都收住了
    expect(find.textContaining('同时还有 1 个进行中'), findsOneWidget);
  });
}
