import 'package:celechron/http/timetable_fetch_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「查询季节 → 归到哪个学期」（2026-09-18）。
///
/// 为什么单独锁：有用户报「选择秋冬学期课程好像会显示春夏学期课程」（v1.4.0 时期）。
/// 课程进哪个学期**只由这条映射决定** —— 它错了，秋冬就会装进春夏的课；
/// 它没错，那问题只可能在"教务返回了什么"（那就该看诊断日志，而不是猜代码）。
void main() {
  const year = '2026-2027';

  test('秋冬的两个季节都归到 -1', () {
    expect(
        TimetableFetchPolicy.semesterKeyForSeason('1|秋', year), '2026-2027-1');
    expect(
        TimetableFetchPolicy.semesterKeyForSeason('1|冬', year), '2026-2027-1');
  });

  test('春夏的两个季节都归到 -2', () {
    expect(
        TimetableFetchPolicy.semesterKeyForSeason('2|春', year), '2026-2027-2');
    expect(
        TimetableFetchPolicy.semesterKeyForSeason('2|夏', year), '2026-2027-2');
  });

  test('四个季节正好落在两个学期里，秋冬与春夏不会互相串', () {
    final keys = ['1|秋', '1|冬', '2|春', '2|夏']
        .map(
            (season) => TimetableFetchPolicy.semesterKeyForSeason(season, year))
        .toSet();
    expect(keys.length, 2, reason: '只有秋冬与春夏两个学期');
    expect(keys.contains('2026-2027-1'), isTrue);
    expect(keys.contains('2026-2027-2'), isTrue);
  });

  test('学期 id 的格式与 Semester 约定一致（学年-1 / 学年-2）', () {
    for (final season in ['1|秋', '1|冬', '2|春', '2|夏']) {
      final key = TimetableFetchPolicy.semesterKeyForSeason(season, year);
      expect(RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(key), isTrue);
    }
  });
}
