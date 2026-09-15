import 'package:celechron/utils/time_helper.dart';

/// ============ 课前提醒的提前量算法 ============
///
/// 用户给的规则（原话）：
///
/// 1. 当一节课前面没有课时，应该提前 **20 分钟**提醒；
/// 2. 当一节课前面有课时，提前 **10 分钟**提醒；
/// 3. 遇到午饭/晚饭时间段**视作一节空课**；
/// 4. 判断一节课前有没有课，根据**空余时间是否大于课间时长**来算。
///
/// 直觉解释：连着上课时（课间只有 10 分钟）需要早一点提醒，因为要收拾东西赶去下一间教室；
/// 而如果前面本来就有大段空闲（或者干脆是今天第一节课、或者隔着午饭），
/// 你就已经在空闲里了，给 10 分钟反而太晚——所以给 20 分钟。
///
/// 这个类是**纯函数**：不碰界面、不碰数据库、不看当前时间，所以能直接单测。
/// 数据源与投递方式（系统日历提醒 / 通知）在调用方决定。
class ClassReminderRule {
  ClassReminderRule({
    this.breakMinutes = defaultBreakMinutes,
    List<TimeWindow>? meals,
  }) : meals = meals ?? defaultMeals;

  /// 课间时长（分钟）。**间隔 ≤ 它就算"连着的两节课"**。
  ///
  /// 为什么是 15：本校实际课间有两种（数据取自校历节次表）——
  /// - **小课间 5 分钟**：第 1→2 节、第 4→5 节、第 7→8 节…
  /// - **大课间 25 分钟**：第 2→3 节（09:35→10:00）、第 8→9 节（15:50→16:15）
  ///
  /// 而实际选课里"多节连堂"很常见，小课间常被连上吞掉 —— 用户描述的现象是
  /// **连堂课的课间基本按 15 分钟算**。所以取 15 作阈值：
  /// 5（小课间）与 15（连堂）都判成"前面有课"→ 提前 10 分钟；
  /// 25（大课间）与 60（午饭/晚饭）判成"前面没课"→ 提前 20 分钟。
  ///
  /// 这个值可配置（[breakMinutes]），将来若学校改排课，改数字即可，不用动逻辑。
  static const int defaultBreakMinutes = 15;

  /// 前面没课 → 提前这么多分钟
  ///
  /// 2026-09-15 用户调整：20 → **30**。
  /// 理由：前面本来就空着，早点提醒更从容（而连着上课时给 30 分钟反而没意义，
  /// 因为你就在教学楼里）。
  static const int leadWithoutPreviousClass = 30;

  /// 前面有课（连着上） → 提前这么多分钟
  static const int leadWithPreviousClass = 10;

  /// 午饭 / 晚饭时段：**视作一节空课**，不当作"前面有课"。
  ///
  /// 默认值取自校历的节次表（第 5 节 12:25 结束、第 6 节 13:25 开始 → 午饭；
  /// 第 11 节 17:50 结束、第 12 节 18:50 开始 → 晚饭）。
  static final List<TimeWindow> defaultMeals = [
    TimeWindow(11 * 60 + 35, 13 * 60 + 25), // 午饭
    TimeWindow(17 * 60 + 0, 18 * 60 + 50), // 晚饭
  ];

  final int breakMinutes;
  final List<TimeWindow> meals;

  /// 这节课该提前几分钟提醒。
  ///
  /// [target] 目标课程；[sameDayClasses] 当天的其它课程（可以包含 target 自己，会被忽略）。
  int leadMinutesFor(ClassSlot target, Iterable<ClassSlot> sameDayClasses) {
    final previous = previousClassBefore(target, sameDayClasses);
    if (previous == null) {
      // 规则 1：今天第一节（或前面没有任何课）
      return leadWithoutPreviousClass;
    }

    // 规则 4：空余时间 > 课间时长 → 视作"前面没课"
    final gapMinutes = target.start.difference(previous.end).inMinutes;
    if (gapMinutes > breakMinutes) return leadWithoutPreviousClass;

    // 规则 3：中间隔着午饭/晚饭 → 视作一节空课，同样"前面没课"
    if (crossesMeal(previous.end, target.start)) {
      return leadWithoutPreviousClass;
    }

    // 规则 2：前面有课且挨得很近
    return leadWithPreviousClass;
  }

  /// 找出 target 之前"最近的一节"课（按开始时间算）；没有则 null。
  ClassSlot? previousClassBefore(
    ClassSlot target,
    Iterable<ClassSlot> sameDayClasses,
  ) {
    ClassSlot? previous;
    for (final candidate in sameDayClasses) {
      if (identical(candidate, target)) continue;
      if (candidate.start == target.start && candidate.end == target.end) {
        continue; // 同一节课（不同实例也视作同一节）
      }
      // 只考虑"在 target 开始之前就已经结束、或至少是更早开始"的课。
      // 用开始时间比较即可：课表里的课按开始时间排，重叠的课不会出现在同一份课表里。
      if (!candidate.start.isBefore(target.start)) continue;
      if (previous == null || candidate.start.isAfter(previous.start)) {
        previous = candidate;
      }
    }
    return previous;
  }

  /// [from] → [to] 这段空档里是否夹着午饭 / 晚饭时段
  bool crossesMeal(DateTime from, DateTime to) {
    if (!to.isAfter(from)) return false;
    final startMinute = from.hour * 60 + from.minute;
    final endMinute = to.hour * 60 + to.minute;
    for (final meal in meals) {
      // 只要空档与某个饭点有重叠，就算夹着
      final overlaps = meal.start < endMinute && meal.end > startMinute;
      if (overlaps) return true;
    }
    return false;
  }
}

/// 一节课的起止（纯数据，避免依赖 Period / Task 这些重对象）
class ClassSlot {
  final DateTime start;
  final DateTime end;

  const ClassSlot(this.start, this.end);

  @override
  String toString() => '${TimeHelper.chineseDateTime(start)}~${short(end)}';

  static String short(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 一天里的一个时间窗（用来表示饭点）
class TimeWindow {
  /// 从 00:00 起的分钟数
  final int start;
  final int end;

  const TimeWindow(this.start, this.end);
}
