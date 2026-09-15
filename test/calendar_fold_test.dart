import 'package:celechron/mod/calendar_fold.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

/// 日程页「上滑收起日历」的判定测试。
///
/// 口径（用户定的）：日程页面上滑 → 日历折成一周；滑回顶部继续下拉 → 展开整月。
/// 这里全是纯逻辑，不碰真实滚动 —— 真机手感还要人工确认。
void main() {
  CalendarFoldGesture fresh() => CalendarFoldGesture();

  /// 一条「手指直接带着动的」竖向滚动通知
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

    test('越界累计中途松手回到顶部会清零（两次小滑动凑不成一次大滑动）', () {
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
      // 从列表中间往下拉：不算（还在往回看，不是想放日历出来）
      expect(
        scroll(g,
            current: CalendarFormat.week,
            pixels: 300,
            delta: -50),
        isNull,
      );
      // 到顶了继续拉：攒够就展开
      expect(
        scroll(g,
            current: CalendarFormat.week,
            pixels: 0,
            delta: -20),
        isNull,
      );
      expect(
        scroll(g,
            current: CalendarFormat.week,
            pixels: 0,
            delta: -20),
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
    test('★ 不是手指带着动的通知一律不算 —— 折叠后列表自动回弹到 0 绝不能当成下拉', () {
      final g = fresh();
      // 折起来之后列表变高、内容不再溢出，位置自动弹回 0：
      // 这种「自动回弹」如果被当成下拉，就会立刻展开 → 一折一展死循环
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

    test('★ 横向通知一律不算 —— TableCalendar 内部是横向翻页的 PageView', () {
      final g = fresh();
      // 它的 pixels 是「第几页」的偏移，拿它判断会让日历莫名其妙折叠
      expect(
        scroll(g,
            current: CalendarFormat.month,
            pixels: 400,
            axis: Axis.horizontal),
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
}
