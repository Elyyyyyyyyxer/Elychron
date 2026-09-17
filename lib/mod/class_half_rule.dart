/// ============ 自定义周次（按周上课）到底属于哪一半学期 ============
///
/// ## 背景：一个真实的 bug
///
/// 研究生院返回的课表里有 `zc`（上课周次，例如 `1-8周`），对应 `Session.customRepeat`
/// 与 `customRepeatWeeks`。原来的排课代码**只看周次数字**决定它落在秋还是冬：
///
/// ```dart
/// day = _dayOfWeekToDays[(week - 1) ~/ 8][...]   // 第 1-8 周一律当上半学期
/// ```
///
/// 但研究生院的 `zc` 是**该课程所在半学期内部**的周次， **只有冬学期才上的课，
/// 它给的也是1-8 周**。于是冬课被排到了秋天：
/// 反馈原话是物理光学实验（只有冬学期才有的课）在日程-接下来页面里显示出问题，
/// 而课表（两周表格）是正常的， 因为课表走的是另一条不按日期展开的路径。
///
/// ## 规则（尽量保守，宁可维持原状）
///
/// - **单半学期**（只有秋 或 只有冬）且**周次全都 ≤ 8** → 按**它自己那一半**为基准；
/// - 其余情况（跨两半的长学期课、或周次里出现 ≥ 9 的全局编号）→ 维持原来的
///   **全局周次**解释（第 1-8 周是上半学期、9-16 周是下半学期）。
///
/// 这样两种编号习惯都能落对：本校研究生院是"半学期内编号"，而
/// 全局编号（1-16）的课程行为完全不变，不会把原本正确的排课改坏。
class ClassHalfRule {
  ClassHalfRule._();

  /// 上半学期在半学期数组里的下标
  static const int firstHalfIndex = 0;

  /// 下半学期在半学期数组里的下标
  static const int secondHalfIndex = 1;

  /// 周次是否看起来是"半学期内编号"（全部 ≤ 8）
  static bool looksHalfRelative(List<int> weeks) =>
      weeks.isNotEmpty && weeks.every((week) => week <= 8);

  /// 该以哪一半为基准；返回 null 表示"按全局周次解释"（调用方沿用原逻辑）。
  static int? baseHalfIndex({
    required bool firstHalf,
    required bool secondHalf,
    required List<int> weeks,
  }) {
    // 跨两半的课：周次本身就是全局的（1-16），不能强行塞进某一半
    if (firstHalf == secondHalf) return null;
    // 周次里出现 ≥ 9：这是全局编号，按老规矩走
    if (!looksHalfRelative(weeks)) return null;
    return firstHalf ? firstHalfIndex : secondHalfIndex;
  }

  /// 给定一个周次，算出它落在半学期数组的哪一半（沿用原公式的语义）。
  static int halfIndexForWeek(int week, {int? baseHalfIndex}) {
    if (baseHalfIndex != null) return baseHalfIndex;
    return (week - 1) ~/ 8;
  }
}
