import 'package:flutter/widgets.dart';

/// ===== 日历折叠：跟手拖动的几何与手感（2026-09-18，纯逻辑，有单测）=====
///
/// 用户要求：「日历折叠优化，更流畅地滑动而不是播放动画。现在只是播放一个无法操纵的
/// 动画，我想要能够跟随手指滑动，有一点点惯性」。
///
/// 原来的做法是把折叠交给 `TableCalendar` 自己的 `month ⇄ week` 切换 ——
/// 它只有两个状态，点一下/滑一下就是播一段 140ms 的动画，手指**控制不了中间过程**。
///
/// 现在的做法：日历用一个「视窗高度」来呈现折叠程度
/// （`foldProgress`：0 = 整月，1 = 只剩聚焦那一周），拖动时这个值跟着手指走、
/// 松手后按速度收敛到两端。为了不出现"折到一半突然跳到第 1 行"的穿帮，
/// 拖动过程中还要把整月视图**往上平移**，让聚焦周一直待在视窗里 ——
/// 这两个量（视窗高度、平移量）就是这里算的，单独抽出来是为了能单测：
/// 行数和行号的 off-by-one 最容易错，错了就是"折起来之后显示的是别的周"。
class CalendarFoldGeometry {
  CalendarFoldGeometry._();

  /// 一周有 7 天
  static const int daysPerWeek = 7;

  /// 月视图有多少行（与 `TableCalendar` 的排布一致：周一起始）。
  ///
  /// `firstWeekdayOfMonth` 取 1..7（周一=1）→ 首行前面要空几格。
  static int monthRowCount(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - DateTime.monday;
    return ((lead + daysInMonth) / daysPerWeek).ceil();
  }

  /// 聚焦那一天落在月视图的第几行（0 起）。
  ///
  /// ⚠️ 必须按**聚焦月**来算，而不是按聚焦日自己所在的月：
  /// `TableCalendar` 在月视图里也会显示上/下月的尾巴，聚焦日可能落在相邻月的那几格上，
  /// 但格子是排在**当前聚焦月**的网格里的。
  static int focusedWeekRow({
    required DateTime focusedMonth,
    required DateTime focusedDay,
  }) {
    final first = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final lead = first.weekday - DateTime.monday; // 0..6，首行前面空几格
    final day = DateTime(focusedDay.year, focusedDay.month, focusedDay.day);
    // 聚焦日相对"聚焦月 1 号"的格子偏移；跨月时会是负数或超出当月天数，这正是我们要的
    final cell = lead + day.difference(first).inDays;
    final rows = monthRowCount(focusedMonth);
    if (cell < 0) return 0;
    final row = cell ~/ daysPerWeek;
    if (row >= rows) return rows - 1;
    return row;
  }

  /// 拖动之后的折叠进度（0..1）。
  ///
  /// [startProgress] 按下时的进度；[dy] 本次的竖向位移（**向上为负**，
  /// 与 Flutter 的 delta 一致）；[range] 手指要走多少像素才算折完一整次。
  static double progressAfterDrag({
    required double startProgress,
    required double dy,
    required double range,
  }) {
    if (range <= 0) return startProgress.clamp(0.0, 1.0);
    // 手指往上走（dy < 0）→ 进度增加 → 日历变矮
    final next = startProgress - dy / range;
    return next.clamp(0.0, 1.0);
  }

  /// 松手之后该停在折起还是展开（这就是"一点点惯性"）。
  ///
  /// - 甩得够快（|v| ≥ [flingVelocity]）→ 顺着甩的方向走，不看进度
  /// - 慢慢松手 → 就近停（超过 [snapThreshold] 就折起）
  static bool settleFolded({
    required double progress,
    required double velocity,
    double snapThreshold = 0.5,
    double flingVelocity = 420,
  }) {
    if (velocity <= -flingVelocity) return true; // 往上甩 → 折起
    if (velocity >= flingVelocity) return false; // 往下甩 → 展开
    return progress >= snapThreshold;
  }

  /// 折叠过程中的**视窗高度**（像素）：整月 [monthRows] 行 → 一周 1 行。
  ///
  /// ⚠️ 这里必须按**像素**算，不能按"行数比例"（我第一版就是按 1/行数 写的，
  /// 忽略了星期行那 20 像素，折到底时会比一周**矮 20 像素**，把日期切掉一条）。
  /// 前提是把 `TableCalendar` 自带的星期行关掉（`daysOfWeekVisible: false`），
  /// 由外面pin 一行自己的 —— 这样"整月 → 一周"就是一个**连续**的裁剪区间，
  /// 也不用担心折完那一刻和「周视图」的高度对不上（两边都是 rowHeight）。
  static double visibleHeight({
    required int monthRows,
    required double rowHeight,
    required double progress,
  }) {
    final full = monthRows * rowHeight;
    final folded = rowHeight;
    return full + (folded - full) * progress.clamp(0.0, 1.0);
  }

  /// 拖动时要把网格往上推多少**像素**，让聚焦周一直留在视窗里。
  ///
  /// 展开时（progress=0）不平移；折完时（progress=1）正好推掉聚焦周上面那几行。
  static double translateOffset({
    required int focusedRow,
    required double rowHeight,
    required double progress,
  }) =>
      focusedRow * rowHeight * progress.clamp(0.0, 1.0);
}

/// 从一条滚动通知里取出判定需要的几样东西。
///
/// 单独抽出来是为了**能测**：真要测 `CalendarController.handleDayListScroll`
/// 得先把 controller 造出来（它依赖 scholar / taskList 两个 Rx），不值当；
/// 而"哪几种通知能用、每个字段对应什么"恰恰是最容易接错的一环
/// （把 `fromUser` 写死成 `true` 就会把"折叠后列表自动回弹"当成用户下拉 → 一折一展死循环）。
class CalendarFoldSignal {
  /// 本次增量：滚动通知是 `scrollDelta`，越界通知是 `overscroll`
  final double delta;

  /// 本次是不是越界通知
  final bool isOverscroll;

  /// 是不是**手指直接带着动**的
  final bool fromUser;

  const CalendarFoldSignal({
    required this.delta,
    required this.isOverscroll,
    required this.fromUser,
  });

  /// 返回 `null` 表示这条通知不该用来判定
  /// （滚动开始/结束、布局变化引起的自动回弹、惯性滑动……）。
  static CalendarFoldSignal? from(ScrollNotification notification) {
    if (notification is OverscrollNotification) {
      return CalendarFoldSignal(
        delta: notification.overscroll,
        isOverscroll: true,
        fromUser: notification.dragDetails != null,
      );
    }
    if (notification is ScrollUpdateNotification) {
      return CalendarFoldSignal(
        delta: notification.scrollDelta ?? 0,
        isOverscroll: false,
        fromUser: notification.dragDetails != null,
      );
    }
    return null;
  }

  /// 是不是一次新的触摸开始了， 要把累加器清零。
  static bool isDragStart(ScrollNotification notification) =>
      notification is ScrollStartNotification &&
      notification.dragDetails != null;
}
