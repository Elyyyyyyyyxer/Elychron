import 'package:celechron/http/timetable_fetch_policy.dart';
import 'package:celechron/http/time_config_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 少打几个请求这套策略的纯逻辑测试（2026-09-17 用户拍板）。
///
/// 起因：教务对**一个时间窗内的请求条数**限流（HTTP 921），而课表是按
/// 学年 × 学期逐个查的， 26 级 2×4=8 次、23 级 4×4=16 次，
/// 再加上成绩/主修/考试/作业/实践，一次刷新 13~21 个请求，经常撞限流。
///
/// 这里的规则决定"哪些请求不用打"，所以边界必须钉死：
/// 今天/昨天、历史/当前学年、缓存优先时不吃"已知为空"的规则。
void main() {
  group('已知为空的学期：当天不再重复问', () {
    const today = '2026-09-17';

    test('今天问过、是空的 → 跳过', () {
      expect(
          TimetableFetchPolicy.shouldSkipKnownEmptyTimetable(
              emptyStamp: today, today: today, preferCache: false),
          isTrue);
    });

    test('昨天问过的 → 不跳过（第二天要再确认一次）', () {
      expect(
          TimetableFetchPolicy.shouldSkipKnownEmptyTimetable(
              emptyStamp: '2026-09-16', today: today, preferCache: false),
          isFalse);
    });

    test('没问过 / 空字符串 → 不跳过', () {
      expect(
          TimetableFetchPolicy.shouldSkipKnownEmptyTimetable(
              emptyStamp: null, today: today, preferCache: false),
          isFalse);
      expect(
          TimetableFetchPolicy.shouldSkipKnownEmptyTimetable(
              emptyStamp: '', today: today, preferCache: false),
          isFalse);
    });

    test('历史学年（preferCache）不吃这条规则， 那条路本来就走缓存', () {
      expect(
          TimetableFetchPolicy.shouldSkipKnownEmptyTimetable(
              emptyStamp: today, today: today, preferCache: true),
          isFalse);
    });
  });

  group('本地日期串', () {
    test('补零、用本地日期（不是 UTC）', () {
      expect(TimetableFetchPolicy.localDayStamp(DateTime(2026, 9, 7)),
          '2026-09-07');
      expect(TimetableFetchPolicy.localDayStamp(DateTime(2026, 12, 31)),
          '2026-12-31');
    });

    test('标记键带上学年与学期，互不串味', () {
      final key = TimetableFetchPolicy.emptyStampKey('2026-2027', '1|秋');
      expect(key, contains('2026-2027'));
      expect(key, contains('1|秋'));
      // 同学年不同学期、同学期不同学年，都必须是不同的键
      expect(
          TimetableFetchPolicy.emptyStampKey('2026-2027', '2|春'), isNot(key));
      expect(
          TimetableFetchPolicy.emptyStampKey('2025-2026', '1|秋'), isNot(key));
    });
  });

  group('历史学年判定（学年从 9 月起算）', () {
    test('9 月之后：本学年就是今年，去年是历史', () {
      final now = DateTime(2026, 9, 17);
      expect(TimetableFetchPolicy.isPastAcademicYear(2025, now), isTrue);
      expect(TimetableFetchPolicy.isPastAcademicYear(2026, now), isFalse,
          reason: '当前学年要照常联网查，才拿得到最新数据');
      expect(TimetableFetchPolicy.isPastAcademicYear(2027, now), isFalse,
          reason: '探针学年（未来）也要查，那是发现"新学年开放了"的唯一途径');
    });

    test('1 月：学年边界还没过，去年 9 月仍是本学年', () {
      final now = DateTime(2027, 1, 5);
      expect(TimetableFetchPolicy.isPastAcademicYear(2026, now), isFalse);
      expect(TimetableFetchPolicy.isPastAcademicYear(2025, now), isTrue);
    });
  });

  group('校历：历史学期不再试远程', () {
    test('过去学年的学期 → 不试远程（校历不会再改）', () {
      final service = TimeConfigService();
      final now = DateTime(2026, 9, 17);
      expect(service.shouldAttemptRemote('2025-2026-1', now: now), isFalse);
      expect(service.shouldAttemptRemote('2025-2026-2', now: now), isFalse);
    });

    test('当前学年 → 该试（具体是否到期由"每周一次"那条规则决定）', () {
      final service = TimeConfigService();
      final now = DateTime(2026, 9, 17);
      expect(service.shouldAttemptRemote('2026-2027-1', now: now), isTrue);
    });

    test('学期 id 写坏了也不崩（当作可以试，交给后面的解析去报错）', () {
      final service = TimeConfigService();
      expect(service.shouldAttemptRemote('乱七八糟', now: DateTime(2026, 9, 17)),
          isTrue);
    });
  });
}
