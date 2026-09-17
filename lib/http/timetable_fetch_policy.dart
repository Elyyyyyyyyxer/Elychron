import 'package:celechron/http/calendar_config_parser.dart'
    show academicYearStartFor;

/// ===== 课表抓取的取数策略（纯逻辑，可单测）=====
///
/// 2026-09-17 用户拍板要"减少对历史学年的探查来减少请求次数"，因为教务对
/// **一个时间窗内的请求条数**限流（HTTP 921），而课表是按学年 × 学期逐个查的：
/// 一次刷新 8~16 个请求，里面一大半是**明知故问**。
///
/// 这里把"哪些请求可以不打"的判断单独抽出来， 它们是纯函数，
/// 边界（今天/昨天、历史/当前学年）都能在单测里钉死，不必等真机复现。
class TimetableFetchPolicy {
  TimetableFetchPolicy._();

  /// "某个学年学期今天问过、是空的"这个标记的键名。
  ///
  /// 中间用 `__` 分隔：学年（`2026-2027`）和学期（`1|秋`）直接拼起来虽然没有歧义，
  /// 但加个分隔符更好读、也更能保证"不同组合不会撞键"。
  static String emptyStampKey(String year, String semester) =>
      'zdbk_TimetableEmptyAt_${year}__$semester';

  /// 本地日期串（yyyy-MM-dd）。
  ///
  /// 用**本地**日期而不是 UTC：对用户来说"今天"是本地的今天，
  /// 用 UTC 会让时区靠东的人在晚上 8 点就"跨天"，白问一遍。
  static String localDayStamp(DateTime now) {
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  /// 要不要**跳过**这次课表请求（因为"今天已经问过、当时是空的"）。
  ///
  /// - [preferCache] 为真时（历史学年）不吃这个规则：那条路本来就走缓存；
  /// - 只认"今天"：明天会再确认一次，足够及时（学期开放不是分钟级的事）。
  static bool shouldSkipKnownEmptyTimetable({
    required String? emptyStamp,
    required String today,
    required bool preferCache,
  }) {
    if (preferCache) return false;
    if (emptyStamp == null || emptyStamp.isEmpty) return false;
    return emptyStamp == today;
  }

  /// 这个学年是不是**已经过去**了（历史学年可以只吃缓存）
  static bool isPastAcademicYear(int academicYearStart, DateTime now) =>
      academicYearStart < academicYearStartFor(now);
}
