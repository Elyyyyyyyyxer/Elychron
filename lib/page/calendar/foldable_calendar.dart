import 'package:celechron/mod/calendar_fold_geometry.dart';
import 'package:celechron/page/calendar/calendar_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';

/// ===== 可跟手折叠的日历（2026-09-18，用户要求）=====
///
/// 用户原话：「日历折叠优化，更加流畅地滑动而不是播放动画。现在只是播放一个无法操纵的
/// 动画，我想要能够跟随手指滑动，有一点点惯性」。
///
/// 原来的折叠 = 让 `TableCalendar` 在 `month ⇄ week` 之间切一下，
/// 它只有两个状态，手指**控制不了中间过程**（只能看它把 140ms 的动画播完）。
///
/// 现在的做法：把表格套进一个**会变矮的视窗**里 ——
/// - 拖动时视窗高度直接跟着手指走（[CalendarFoldGeometry.progressAfterDrag]）；
/// - 同时把整月视图往上平移，让**聚焦那一周**始终留在视窗里，
///   这样"折到一半"看起来就是日历被收上去，而不是突然换成别的周；
/// - 松手按速度收敛（[CalendarFoldGeometry.settleFolded]）：往上甩就折起、往下甩就展开、
///   慢慢松手则就近停 —— 这就是"一点点惯性"。
///
/// 折到位之后才把 `calendarFormat` 切成 `week`（真正少画几行，省掉无谓的布局），
/// 而那时视窗里显示的正好就是聚焦周，所以**看不出切换**。
class FoldableCalendar extends StatefulWidget {
  const FoldableCalendar({
    super.key,
    required this.controller,
    required this.child,
    required this.rowHeight,
  });

  final CalendarController controller;
  final Widget child;

  /// 与 `TableCalendar` 一致的行高（算视窗高度要用）
  final double rowHeight;

  @override
  State<FoldableCalendar> createState() => _FoldableCalendarState();
}

class _FoldableCalendarState extends State<FoldableCalendar>
    with SingleTickerProviderStateMixin {
  /// 松手后收敛过去用多久。比原来表格自带的 140ms 稍长一点：
  /// 跟手拖完再接一段短动画，长一点点反而更像"惯性收尾"。
  static const Duration _settleDuration = Duration(milliseconds: 190);

  /// 手指走多少像素算"折完一次"。
  ///
  /// 月视图 5 行时整月 5×48 = 240、一周 48，差 192。
  /// 取 96（约一半）—— 有意识地划一下就到底，不用把手机滑出屏幕。
  static const double _dragRange = 96;

  late final AnimationController _fold;
  double _dragStart = 0;
  late bool _wasFolded;
  late final Worker _formatWorker;

  @override
  void initState() {
    super.initState();
    _wasFolded = widget.controller.calendarFormat.value == CalendarFormat.week;
    _fold = AnimationController(
      vsync: this,
      duration: _settleDuration,
      value: _wasFolded ? 1 : 0,
    );
    // 折叠状态一变（不管是拖动收尾、点提示条、还是上滑列表触发的），
    // 都把视窗动画到对应的那一端 —— 动画只在这里发生，逻辑保持单一来源。
    _formatWorker = ever(widget.controller.calendarFormat, (_) {
      final folded =
          widget.controller.calendarFormat.value == CalendarFormat.week;
      _wasFolded = folded;
      _fold.animateTo(
        folded ? 1 : 0,
        duration: _settleDuration,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _formatWorker.dispose();
    _fold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragStart = _fold.value,
      onVerticalDragUpdate: (details) {
        _fold.value = CalendarFoldGeometry.progressAfterDrag(
          startProgress: _dragStart,
          dy: details.delta.dy,
          range: _dragRange,
        );
      },
      onVerticalDragEnd: (details) {
        final folded = CalendarFoldGeometry.settleFolded(
          progress: _fold.value,
          velocity: details.velocity.pixelsPerSecond.dy,
        );
        // 交给 controller 改状态，动画由上面那个 ever 统一收尾
        widget.controller.setFolded(folded);
      },
      child: ListenableBuilder(
        listenable: _fold,
        builder: (BuildContext context, Widget? child) => _window(child!),
        child: widget.child,
      ),
    );
  }

  /// 变矮的视窗：高度随进度走，同时把聚焦周顶到视窗里
  Widget _window(Widget child) {
    final focusedDay = widget.controller.focusedDay.value;
    final rows = CalendarFoldGeometry.monthRowCount(focusedDay);
    final folded =
        widget.controller.calendarFormat.value == CalendarFormat.week;
    // 折到位之后表格自己就只画那一周了，不能再平移（否则会把那行推出视窗）
    final translate = folded
        ? 0.0
        : CalendarFoldGeometry.translateOffset(
            focusedRow: CalendarFoldGeometry.focusedWeekRow(
              focusedMonth: focusedDay,
              focusedDay: focusedDay,
            ),
            rowHeight: widget.rowHeight,
            progress: _fold.value,
          );
    return SizedBox(
      height: CalendarFoldGeometry.visibleHeight(
        monthRows: rows,
        rowHeight: widget.rowHeight,
        progress: _fold.value,
      ),
      child: ClipRect(
        child: Transform.translate(
          offset: Offset(0, -translate),
          child: child,
        ),
      ),
    );
  }
}
