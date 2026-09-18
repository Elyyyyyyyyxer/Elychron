import 'package:celechron/mod/calendar_fold_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 日历折叠的几何与手感（2026-09-18，用户要求"跟手滑动 + 一点点惯性"）。
///
/// 「折到一半显示成别的周」这种穿帮，根源都是行数/行号算错一格，
/// 所以这一组测试盯的就是这两件事。
void main() {
  group('月视图行数', () {
    test('2026 年 9 月：1 号是周二 → 首行空 1 格，31 天 → 5 行', () {
      expect(CalendarFoldGeometry.monthRowCount(DateTime(2026, 9, 1)), 5);
    });

    test('2026 年 2 月：28 天且正好从周一开始 → 4 行', () {
      // 2026-02-01 是周日，所以首行空 6 格 → 34 格 → 5 行
      expect(CalendarFoldGeometry.monthRowCount(DateTime(2026, 2, 1)), 5);
    });

    test('永远是 4~6 行（不会算出 0 或 7）', () {
      for (var month = 1; month <= 12; month++) {
        final rows =
            CalendarFoldGeometry.monthRowCount(DateTime(2026, month, 1));
        expect(rows, inInclusiveRange(4, 6), reason: '2026-$month');
      }
    });
  });

  group('聚焦周的行号', () {
    test('9/17 落在第三行（14~20 那一周）', () {
      expect(
        CalendarFoldGeometry.focusedWeekRow(
          focusedMonth: DateTime(2026, 9, 1),
          focusedDay: DateTime(2026, 9, 17),
        ),
        2,
      );
    });

    test('9/14（周一）与 9/20（周日）在同一行', () {
      int row(int day) => CalendarFoldGeometry.focusedWeekRow(
            focusedMonth: DateTime(2026, 9, 1),
            focusedDay: DateTime(2026, 9, day),
          );
      expect(row(14), row(20));
    });

    test('9/1 在第一行、9/30 在最后一行', () {
      expect(
        CalendarFoldGeometry.focusedWeekRow(
          focusedMonth: DateTime(2026, 9, 1),
          focusedDay: DateTime(2026, 9, 1),
        ),
        0,
      );
      final last = CalendarFoldGeometry.focusedWeekRow(
        focusedMonth: DateTime(2026, 9, 1),
        focusedDay: DateTime(2026, 9, 30),
      );
      expect(
          last, CalendarFoldGeometry.monthRowCount(DateTime(2026, 9, 1)) - 1);
    });
  });

  group('拖动进度', () {
    test('往上拖（dy<0）→ 进度增加，往下拖 → 减少', () {
      expect(
        CalendarFoldGeometry.progressAfterDrag(
            startProgress: 0.5, dy: -30, range: 120),
        greaterThan(0.5),
      );
      expect(
        CalendarFoldGeometry.progressAfterDrag(
            startProgress: 0.5, dy: 30, range: 120),
        lessThan(0.5),
      );
    });

    test('拖出范围会被夹在 0..1（不会越界到负数或 >1）', () {
      expect(
        CalendarFoldGeometry.progressAfterDrag(
            startProgress: 0.9, dy: -500, range: 120),
        1.0,
      );
      expect(
        CalendarFoldGeometry.progressAfterDrag(
            startProgress: 0.1, dy: 500, range: 120),
        0.0,
      );
    });

    test('range 传 0 时不炸，原样返回', () {
      expect(
        CalendarFoldGeometry.progressAfterDrag(
            startProgress: 0.42, dy: -50, range: 0),
        0.42,
      );
    });
  });

  group('松手后的收敛（惯性）', () {
    test('往上甩 → 折起（哪怕只拖了一点点）', () {
      expect(
        CalendarFoldGeometry.settleFolded(progress: 0.1, velocity: -900),
        isTrue,
      );
    });

    test('往下甩 → 展开（哪怕已经拖到一半以上）', () {
      expect(
        CalendarFoldGeometry.settleFolded(progress: 0.9, velocity: 900),
        isFalse,
      );
    });

    test('慢慢松手 → 就近停', () {
      expect(CalendarFoldGeometry.settleFolded(progress: 0.6, velocity: 0),
          isTrue);
      expect(CalendarFoldGeometry.settleFolded(progress: 0.4, velocity: 0),
          isFalse);
      expect(
          CalendarFoldGeometry.settleFolded(progress: 0.5, velocity: 0), isTrue,
          reason: '正好一半算折起（与 0.5 阈值一致）');
    });
  });

  group('视窗高度与平移（按像素算）', () {
    const rowHeight = 48.0;

    test('不折时高度 = 整月，且不平移', () {
      expect(
        CalendarFoldGeometry.visibleHeight(
            monthRows: 5, rowHeight: rowHeight, progress: 0),
        closeTo(5 * rowHeight, 1e-9),
      );
      expect(
        CalendarFoldGeometry.translateOffset(
            focusedRow: 3, rowHeight: rowHeight, progress: 0),
        0,
      );
    });

    test('折完时高度正好是一行（和周视图一样高，切换时不跳）', () {
      expect(
        CalendarFoldGeometry.visibleHeight(
            monthRows: 5, rowHeight: rowHeight, progress: 1),
        closeTo(rowHeight, 1e-9),
      );
    });

    test('折完时"平移量 + 视窗高度"刚好等于聚焦周那一行', () {
      const focused = 2;
      final translate = CalendarFoldGeometry.translateOffset(
          focusedRow: focused, rowHeight: rowHeight, progress: 1);
      final height = CalendarFoldGeometry.visibleHeight(
          monthRows: 5, rowHeight: rowHeight, progress: 1);
      expect(translate, closeTo(focused * rowHeight, 1e-9));
      // 视窗 = [translate, translate + height]，正好是一行的区间
      expect(translate + height, closeTo((focused + 1) * rowHeight, 1e-9));
    });

    test('进度超出 0..1 会被夹住（拖过头不会算出负高度）', () {
      expect(
        CalendarFoldGeometry.visibleHeight(
            monthRows: 5, rowHeight: rowHeight, progress: 2),
        closeTo(rowHeight, 1e-9),
      );
      expect(
        CalendarFoldGeometry.visibleHeight(
            monthRows: 5, rowHeight: rowHeight, progress: -1),
        closeTo(5 * rowHeight, 1e-9),
      );
    });
  });
}
