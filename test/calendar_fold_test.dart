import 'package:celechron/mod/calendar_fold.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

/// 日程页上滑收起日历的判定测试。
///
/// 口径（用户定的）：日程页面上滑 → 日历折成一周；滑回顶部继续下拉 → 展开整月。
/// 前四组是纯逻辑（不碰真实滚动）；最后一组拿真的 `ScrollNotification` 对象
/// 验通知 → 判定参数的映射， 真机手感还要人工确认。
void main() {
  CalendarFoldGesture fresh() => CalendarFoldGesture();

  /// 一条手指直接带着动的竖向滚动通知
  CalendarFormat? scroll(
    CalendarFoldGesture g, {
    required CalendarFormat current,
    required double pixels,
    double delta = 0,
    bool isOverscroll = false,
    bool fromUser = true,
    Axis axis = Axis.vertical,
  }) =>
      g.decide(
        current: current,
        axis: axis,
        pixels: pixels,
        delta: delta,
        isOverscroll: isOverscroll,
        fromUser: fromUser,
      );

  group('折叠：上滑收起日历', () {
    test('列表向上滑出去一段 → 折成一周', () {
      final g = fresh();
      expect(
        scroll(g,
            current: CalendarFormat.month,
            pixels: CalendarFoldGesture.threshold + 1),
        CalendarFormat.week,
      );
    });

    test('只滑一点点不折（阈值内不误触）', () {
      final g = fresh();
      expect(
        scroll(g,
            current: CalendarFormat.month,
            pixels: CalendarFoldGesture.threshold - 1),
        isNull,
      );
    });

    test('列表滚不动（当天只有一两条）时，往上顶的越界量累计够了也折', () {
      final g = fresh();
      // 每次 10px，列表内容不够长、pixels 一直贴着 0
      for (var i = 0; i < 2; i++) {
        expect(
          scroll(g,
              current: CalendarFormat.month,
              pixels: 0,
              delta: 10,
              isOverscroll: true),
          isNull,
        );
      }
      expect(
        scroll(g,
            current: CalendarFormat.month,
            pixels: 0,
            delta: 10,
            isOverscroll: true),
        CalendarFormat.week,
      );
    });

    test('越界累计中途回到顶部会清零（两次小滑动凑不成一次大滑动）', () {
      final g = fresh();
      scroll(g,
          current: CalendarFormat.month,
          pixels: 0,
          delta: 20,
          isOverscroll: true);
      // 回到顶部（正常滚动，不是越界）→ 清零
      scroll(g, current: CalendarFormat.month, pixels: 0, delta: 0);
      expect(
        scroll(g,
            current: CalendarFormat.month,
            pixels: 0,
            delta: 20,
            isOverscroll: true),
        isNull,
      );
    });

    test('startDrag 清空累加器（新手势从头算）', () {
      final g = fresh();
      scroll(g,
          current: CalendarFormat.month,
          pixels: 0,
          delta: 20,
          isOverscroll: true);
      g.startDrag();
      expect(
        scroll(g,
            current: CalendarFormat.month,
            pixels: 0,
            delta: 20,
            isOverscroll: true),
        isNull,
      );
    });
  });

  group('展开：回到顶部下拉', () {
    test('折起来后，回到顶部继续下拉 → 展开整月', () {
      final g = fresh();
      // 从列表中间往下拉：不算（还在往回看，不是想把日历放出来）
      expect(
        scroll(g, current: CalendarFormat.week, pixels: 300, delta: -50),
        isNull,
      );
      // 到顶了继续拉：攒够就展开
      expect(
        scroll(g, current: CalendarFormat.week, pixels: 0, delta: -20),
        isNull,
      );
      expect(
        scroll(g, current: CalendarFormat.week, pixels: 0, delta: -20),
        CalendarFormat.month,
      );
    });

    test('在列表中间往下拉不会展开（否则看着看着日历就冒出来了）', () {
      final g = fresh();
      expect(
        scroll(g, current: CalendarFormat.week, pixels: 120, delta: -100),
        isNull,
      );
      expect(
        scroll(g, current: CalendarFormat.week, pixels: 8, delta: -100),
        isNull,
      );
    });

    test('顶部往上滑（delta>0）不会展开', () {
      final g = fresh();
      expect(
        scroll(g, current: CalendarFormat.week, pixels: 0, delta: 40),
        isNull,
      );
    });
  });

  group('必须滤掉的两种情况', () {
    test('★ 不是手指带着动的通知一律不算， 折叠后列表自动回弹到 0 绝不能当成下拉', () {
      final g = fresh();
      // 折起来之后列表变高、内容不再溢出，位置自动弹回 0：
      // 这种自动回弹如果被当成下拉，就会立刻展开 → 一折一展死循环
      expect(
        scroll(g,
            current: CalendarFormat.week,
            pixels: 0,
            delta: -100,
            fromUser: false),
        isNull,
      );
      // 反向同理：惯性滑动也不该触发折叠
      expect(
        scroll(g,
            current: CalendarFormat.month,
            pixels: 400,
            delta: 50,
            fromUser: false),
        isNull,
      );
    });

    test('★ 横向通知一律不算， TableCalendar 内部是横向翻页的 PageView', () {
      final g = fresh();
      // 它的 pixels 是第几页的偏移，拿它判断会让日历莫名其妙折叠
      expect(
        scroll(g,
            current: CalendarFormat.month, pixels: 400, axis: Axis.horizontal),
        isNull,
      );
      expect(
        scroll(g,
            current: CalendarFormat.week,
            pixels: 0,
            delta: -100,
            axis: Axis.horizontal),
        isNull,
      );
    });
  });

  group('边界', () {
    test('已经是周视图时不会再返回周', () {
      final g = fresh();
      expect(
        scroll(g, current: CalendarFormat.week, pixels: 500, delta: 10),
        isNull,
      );
    });

    test('已经是月视图时往下拉不会返回月', () {
      final g = fresh();
      expect(
        scroll(g, current: CalendarFormat.month, pixels: 0, delta: -100),
        isNull,
      );
    });

    test('阈值就是这个数（改动要连着注释一起重新想）', () {
      // 28：比"手滑"大，比"有意识划一下"小
      expect(CalendarFoldGesture.threshold, 28);
      expect(CalendarFoldGesture.topTolerance, 1);
    });
  });

  // ===== 通知 → 判定参数 的映射 =====
  //
  // 这一层最容易接错：把 fromUser 写死成 true 就会把"折叠后列表自动回弹"
  // 当成用户下拉 → 一折一展死循环。所以拿**真的通知对象**来测。
  //
  // 这个 Flutter 版本里 `ScrollNotification.context` 是 required 非空的，
  // 所以这组只能用 testWidgets（pump 一个 Builder 拿一个真 context）。
  group('ScrollNotification 映射', () {
    FixedScrollMetrics metrics({double pixels = 120}) => FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 2000,
          pixels: pixels,
          viewportDimension: 500,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 3,
        );

    Future<BuildContext> contextOf(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      }));
      return ctx;
    }

    final fingerDown = DragUpdateDetails(globalPosition: Offset.zero);

    ScrollUpdateNotification update(
      BuildContext context, {
      double pixels = 120,
      double delta = 0,
      DragUpdateDetails? drag,
    }) =>
        ScrollUpdateNotification(
          metrics: metrics(pixels: pixels),
          context: context,
          scrollDelta: delta,
          dragDetails: drag,
        );

    OverscrollNotification over(
      BuildContext context, {
      double pixels = 0,
      double overscroll = 0,
      DragUpdateDetails? drag,
    }) =>
        OverscrollNotification(
          metrics: metrics(pixels: pixels),
          context: context,
          overscroll: overscroll,
          dragDetails: drag,
        );

    ScrollStartNotification start(
      BuildContext context, {
      DragStartDetails? drag,
    }) =>
        ScrollStartNotification(
          metrics: metrics(),
          context: context,
          dragDetails: drag,
        );

    testWidgets('手指带着滚 → fromUser，增量取 scrollDelta', (tester) async {
      final ctx = await contextOf(tester);
      final s =
          CalendarFoldSignal.from(update(ctx, delta: 7, drag: fingerDown))!;
      expect(s.fromUser, isTrue);
      expect(s.delta, 7);
      expect(s.isOverscroll, isFalse);
    });

    testWidgets('★ 没有 dragDetails 的滚动（惯性 / 布局变化后的自动回弹）→ fromUser 为假',
        (tester) async {
      final ctx = await contextOf(tester);
      final s = CalendarFoldSignal.from(update(ctx, pixels: 0, delta: -100))!;
      expect(s.fromUser, isFalse);
      // decide 拿到它必须什么都不做
      expect(
        fresh().decide(
          current: CalendarFormat.week,
          axis: Axis.vertical,
          pixels: 0,
          delta: s.delta,
          isOverscroll: s.isOverscroll,
          fromUser: s.fromUser,
        ),
        isNull,
      );
    });

    testWidgets('越界通知 → 增量取 overscroll（不是 scrollDelta）', (tester) async {
      final ctx = await contextOf(tester);
      final s =
          CalendarFoldSignal.from(over(ctx, overscroll: 13, drag: fingerDown))!;
      expect(s.delta, 13);
      expect(s.isOverscroll, isTrue);
      expect(s.fromUser, isTrue);
    });

    testWidgets('惯性撞到头的越界（没有 dragDetails）→ fromUser 为假', (tester) async {
      final ctx = await contextOf(tester);
      final s = CalendarFoldSignal.from(over(ctx, overscroll: 13))!;
      expect(s.fromUser, isFalse);
    });

    testWidgets('滚动开始/结束通知不参与判定', (tester) async {
      final ctx = await contextOf(tester);
      expect(
        CalendarFoldSignal.from(
            ScrollEndNotification(metrics: metrics(), context: ctx)),
        isNull,
      );
      expect(CalendarFoldSignal.from(start(ctx)), isNull);
    });

    testWidgets('只有"手按下去"的滚动开始才算新手势（要清累加器）', (tester) async {
      final ctx = await contextOf(tester);
      expect(
        CalendarFoldSignal.isDragStart(start(ctx, drag: DragStartDetails())),
        isTrue,
      );
      expect(CalendarFoldSignal.isDragStart(start(ctx)), isFalse);
      expect(
        CalendarFoldSignal.isDragStart(update(ctx, delta: 1, drag: fingerDown)),
        isFalse,
      );
    });

    testWidgets('★ 端到端：折叠后列表自动回弹到 0 不会把日历又展开', (tester) async {
      final ctx = await contextOf(tester);
      final g = fresh();
      // 折叠之后列表变高，位置自动弹回 0
      final signal =
          CalendarFoldSignal.from(update(ctx, pixels: 0, delta: -300))!;
      expect(
        g.decide(
          current: CalendarFormat.week,
          axis: Axis.vertical,
          pixels: 0,
          delta: signal.delta,
          isOverscroll: signal.isOverscroll,
          fromUser: signal.fromUser,
        ),
        isNull,
      );
    });
  });
}
