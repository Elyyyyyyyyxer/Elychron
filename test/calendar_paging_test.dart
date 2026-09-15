import 'package:celechron/mod/calendar_paging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

/// 日历横向翻页：阈值判定 + 翻页后的 focusedDay。
void main() {
  group('翻页后的 focusedDay', () {
    test('月视图：整月挪', () {
      expect(
        shiftedFocusedDay(DateTime(2026, 9, 15), CalendarFormat.month, 1),
        DateTime(2026, 10, 15),
      );
      expect(
        shiftedFocusedDay(DateTime(2026, 9, 15), CalendarFormat.month, -1),
        DateTime(2026, 8, 15),
      );
    });

    test('★ 月视图跨年（12 月往后 / 1 月往前）', () {
      expect(
        shiftedFocusedDay(DateTime(2026, 12, 10), CalendarFormat.month, 1),
        DateTime(2027, 1, 10),
      );
      expect(
        shiftedFocusedDay(DateTime(2026, 1, 10), CalendarFormat.month, -1),
        DateTime(2025, 12, 10),
      );
    });

    test('★ 日期按目标月长度收口，不会被 Dart 规范化成下个月', () {
      // 1 月 31 日往后一个月：应该是 2 月 28 日，而不是 3 月 3 日
      expect(
        shiftedFocusedDay(DateTime(2026, 1, 31), CalendarFormat.month, 1),
        DateTime(2026, 2, 28),
      );
      // 闰年 2 月 29 日
      expect(
        shiftedFocusedDay(DateTime(2028, 1, 31), CalendarFormat.month, 1),
        DateTime(2028, 2, 29),
      );
      // 3 月 31 日往前一个月 → 2 月 28 日
      expect(
        shiftedFocusedDay(DateTime(2026, 3, 31), CalendarFormat.month, -1),
        DateTime(2026, 2, 28),
      );
    });

    test('周视图：按 7 天挪（不是按整月）', () {
      expect(
        shiftedFocusedDay(DateTime(2026, 9, 15), CalendarFormat.week, 1),
        DateTime(2026, 9, 22),
      );
      expect(
        shiftedFocusedDay(DateTime(2026, 9, 15), CalendarFormat.week, -1),
        DateTime(2026, 9, 8),
      );
    });

    test('双周视图：按 14 天挪', () {
      expect(
        shiftedFocusedDay(DateTime(2026, 9, 15), CalendarFormat.twoWeeks, 1),
        DateTime(2026, 9, 29),
      );
    });

    test('direction = 0 原样返回', () {
      final day = DateTime(2026, 9, 15);
      expect(shiftedFocusedDay(day, CalendarFormat.month, 0), day);
    });

    test('连着往一个方向翻 12 次会回到一年后（不会漂）', () {
      var day = DateTime(2026, 1, 31);
      for (var i = 0; i < 12; i++) {
        day = shiftedFocusedDay(day, CalendarFormat.month, 1);
      }
      // 1/31 → 2/28 → 3/28 → … → 次年 1/28（日期被收口后不再回到 31，这是预期行为）
      expect(day.year, 2027);
      expect(day.month, 1);
      expect(day.day, 28);
    });
  });

  group('ModSwipePager 阈值', () {
    Future<int?> drag(WidgetTester tester, double dx, {double dy = 0}) async {
      int? shifted;
      await tester.pumpWidget(
        CupertinoApp(
          home: ModSwipePager(
            threshold: 90,
            onShift: (d) => shifted = d,
            child: const SizedBox(width: 400, height: 300),
          ),
        ),
      );
      await tester.drag(
          find.byType(ModSwipePager), Offset(dx, dy),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      return shifted;
    }

    testWidgets('划得不够远 → 不翻页', (tester) async {
      expect(await drag(tester, -60), isNull);
      expect(await drag(tester, 60), isNull);
    });

    testWidgets('划够远了 → 往左划翻下一页、往右划翻上一页', (tester) async {
      expect(await drag(tester, -150), 1);
      expect(await drag(tester, 150), -1);
    });

    testWidgets('★ 竖向拖动不会触发横向翻页', (tester) async {
      expect(await drag(tester, 0, dy: -200), isNull);
    });
  });
}
