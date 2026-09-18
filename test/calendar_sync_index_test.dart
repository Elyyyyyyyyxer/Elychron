import 'package:celechron/model/calendar_to_system.dart';
import 'package:celechron/model/period.dart';
import 'package:flutter_test/flutter_test.dart';

/// 系统日历同步的「稳定键」（2026-09-18 修「同步会重复添加而不是覆盖」）。
///
/// 背景：以前每次同步都新建事件（不带 eventId），每同步一次就多出整套课表。
/// 现在把「稳定键 → 系统日历事件 ID」存起来，同一个键下次是**更新**、不再新建；
/// 这次没用到的事件会被删掉。
///
/// 这里锁的就是"键必须由内容唯一决定"这件事 —— 如果它不稳定，
/// 升级一次所有键都变，课表又会被整套重建（用户看到的还是"重复添加"）。
void main() {
  Period makePeriod({
    String summary = '数学分析（甲）Ⅰ（H）',
    String location = '紫金港东1A-403',
    DateTime? start,
    DateTime? end,
  }) {
    final period = Period(
      summary: summary,
      location: location,
      startTime: start ?? DateTime(2026, 9, 14, 8, 0),
      endTime: end ?? DateTime(2026, 9, 14, 9, 35),
      type: PeriodType.classes,
    );
    return period;
  }

  test('同样的内容 → 同样的键（可重复调用）', () {
    final a = CalendarToSystemManager.periodKey(makePeriod());
    final b = CalendarToSystemManager.periodKey(makePeriod());
    expect(a, b);
    expect(a.length, 16, reason: '16 位十六进制，便于持久化与肉眼比对');
    expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(a), isTrue);
  });

  test('时间不同 → 键不同（改过课的时间就是新的一件）', () {
    final base = CalendarToSystemManager.periodKey(makePeriod());
    final moved = CalendarToSystemManager.periodKey(makePeriod(
      start: DateTime(2026, 9, 14, 10, 0),
      end: DateTime(2026, 9, 14, 11, 35),
    ));
    expect(moved, isNot(base));
  });

  test('地点不同 / 课程名不同 → 键不同', () {
    final base = CalendarToSystemManager.periodKey(makePeriod());
    expect(
        CalendarToSystemManager.periodKey(makePeriod(location: '紫金港东1A-309')),
        isNot(base));
    expect(CalendarToSystemManager.periodKey(makePeriod(summary: '线性代数Ⅰ（H）')),
        isNot(base));
  });

  test('带范围的键：前缀能认出属于哪个范围，且不同范围不会撞', () {
    final period = makePeriod();
    final autumn = CalendarToSystemManager.scopedKey('2026-2027秋冬', period);
    final spring = CalendarToSystemManager.scopedKey('2026-2027春夏', period);
    expect(
        autumn.startsWith(CalendarToSystemManager.scopePrefixOf('2026-2027秋冬')),
        isTrue);
    expect(
        spring.startsWith(CalendarToSystemManager.scopePrefixOf('2026-2027秋冬')),
        isFalse,
        reason: '清理时靠前缀判断"这条该不该动"，撞了就会误删');
    expect(autumn, isNot(spring));
  });

  test('全部学期（scope=all）也是一个独立范围', () {
    final period = makePeriod();
    expect(
        CalendarToSystemManager.scopedKey('all', period)
            .startsWith(CalendarToSystemManager.scopePrefixOf('all')),
        isTrue);
  });
}
