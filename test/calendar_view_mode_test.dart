import 'package:celechron/http/calendar_config_parser.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/page/calendar/calendar_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 右上角「切换视图」按钮的方向。
///
/// 这里锁的是一个真实出现过的方向错：原来是
/// `current == calendar ? schedule : calendar`，在「接下来」时落到 else，
/// 一点就跳到**日历**，而不是用户想看的**课表**。
void main() {
  test('在「接下来」时点它 → 去课表（不是日历）', () {
    expect(
      CalendarController.toggledViewMode(
          CalendarViewMode.upcoming, CalendarViewMode.upcoming),
      CalendarViewMode.schedule,
    );
  });

  test('在「日历」时点它 → 去课表', () {
    expect(
      CalendarController.toggledViewMode(
          CalendarViewMode.calendar, CalendarViewMode.calendar),
      CalendarViewMode.schedule,
    );
  });

  test('已在课表时点它 → 回到进来之前的那个面', () {
    expect(
      CalendarController.toggledViewMode(
          CalendarViewMode.schedule, CalendarViewMode.upcoming),
      CalendarViewMode.upcoming,
    );
    expect(
      CalendarController.toggledViewMode(
          CalendarViewMode.schedule, CalendarViewMode.calendar),
      CalendarViewMode.calendar,
    );
  });

  test('来回切两次回到原处', () {
    // 接下来 → 课表 → 接下来
    var current = CalendarViewMode.upcoming;
    final before = current;
    current = CalendarController.toggledViewMode(current, before);
    expect(current, CalendarViewMode.schedule);
    current = CalendarController.toggledViewMode(current, before);
    expect(current, CalendarViewMode.upcoming);
  });

  test('没套过校历的学期不能被当成「即将开学」', () {
    // 陷阱：Semester.firstDay 在没有校历时返回「求值那一刻的现在」，
    // 而判断时捕获的 now 更早 —— 于是它恒满足 isAfter(now)。
    // 实测后果：课表页标题出现「未开学 · 25-26春夏」这种张冠李戴。
    final bare = Semester('2025-2026春夏');
    expect(bare.hasCalendar, isFalse);

    // firstDay 退化成「求值那一刻的现在」——这就是它恒满足 isAfter(now) 的原因。
    // 不断言严格先后（两次取 now 可能落在同一毫秒），只断言它约等于当下。
    final now = DateTime.now();
    expect(bare.firstDay.difference(now).inSeconds.abs(), lessThan(5));

    // 套过校历之后才是真实日期
    final configured = Semester('2026-2027秋冬');
    applyCalendarConfig(
      buildSafeDefaultCalendarConfig('2026-2027-1'),
      configured,
      <DateTime, String>{},
      context: '虚构学期',
    );
    expect(configured.hasCalendar, isTrue);
    expect(configured.firstDay.year, 2026);
    expect(configured.lastDay.isAfter(configured.firstDay), isTrue);
  });
}
