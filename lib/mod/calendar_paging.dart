import 'package:flutter/cupertino.dart';
import 'package:table_calendar/table_calendar.dart';

/// 日历横向翻页：**要有意识地划够一段才翻**（用户反馈"老是划错"）。
///
/// 为什么不能直接调库里的阈值：`SimpleSwipeConfig.horizontalThreshold` 只在
/// `onHorizontalSwipe` 那条路上生效，而 TableCalendar 的月份翻页走的是**内部
/// PageView 自己的手势**（`PageScrollPhysics`），根本不过那个阈值 —— 手指一带
/// 就翻页，还可能一口气翻好几页。库也没暴露 PageView 的 physics。
///
/// 所以做法是：把内置的横向滑动手势关掉（`AvailableGestures.verticalSwipe`，
/// 竖向那条「整月 ⇄ 一周」仍然保留），再自己套一层带阈值的横向手势。
class ModSwipePager extends StatefulWidget {
  final Widget child;

  /// 划多远才算一次翻页（**逻辑像素**）。
  ///
  /// 注意别拿 adb 的 `input swipe` 来试：那是**设备像素**，这台机器 1080 宽
  /// ÷ 3 = 360 逻辑像素，所以 220 设备像素只有 73 逻辑像素 —— 够不着阈值，
  /// 看着就像"手势没生效"（我就在这上面绕了好几圈）。
  final double threshold;

  /// 快速轻扫的最小位移：短但很快的一挥也算（否则要划满 90px 才翻，手感发闷）
  final double flickMinDistance;

  /// 快速轻扫的最低速度（逻辑像素/秒）
  final double flickVelocity;

  /// 翻页回调：`-1` 上一页、`+1` 下一页
  final void Function(int direction) onShift;

  const ModSwipePager({
    super.key,
    required this.child,
    required this.onShift,
    this.threshold = 90,
    this.flickMinDistance = 40,
    this.flickVelocity = 900,
  });

  @override
  State<ModSwipePager> createState() => _ModSwipePagerState();
}

class _ModSwipePagerState extends State<ModSwipePager> {
  double _startX = 0;
  double _dx = 0;

  void _onStart(DragStartDetails details) {
    _startX = details.globalPosition.dx;
    _dx = 0;
  }

  void _onUpdate(DragUpdateDetails details) {
    _dx = details.globalPosition.dx - _startX;
  }

  void _onEnd(DragEndDetails details) {
    final moved = _dx.abs();
    final velocity = (details.primaryVelocity ?? 0).abs();
    // 要么划够远，要么短促但够快的一挥（后者也是"有意识"的动作）
    final flicked =
        moved >= widget.flickMinDistance && velocity >= widget.flickVelocity;
    if (moved >= widget.threshold || flicked) {
      widget.onShift(_dx < 0 ? 1 : -1);
    }
    _dx = 0;
  }

  void _onCancel() {
    _dx = 0;
  }

  @override
  Widget build(BuildContext context) {
    // 必须用 GestureDetector（要**赢下手势仲裁**），不能图省事用 Listener：
    //
    // 首页那 5 个标签是外层一个 PageView，它也在抢横向滑动。用 Listener 只是旁听、
    // 不参与仲裁，长距离横划就会被外层抢走 —— **实测真的会误切到「待办」标签**。
    // 用横向拖拽识别器把这一片的手势占住，外层就拿不到了；代价是：
    // 没划够阈值时什么也不发生（这正是用户要的"别那么灵敏"）。
    //
    // opaque：日历里只有日期格子是实心可命中的，格子之间的缝用 deferToChild 收不到手势。
    // 它只挡住**它后面**的兄弟节点（这里没有），子节点的手势（点日期、竖向切整月/一周）
    // 仍然先命中，不受影响。
    return GestureDetector(
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onCancel,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}

/// 横向翻页后新的 `focusedDay`（纯逻辑，有单测）。
///
/// - 周视图 / 双周视图：按 7 / 14 天挪，符号方向连续（否则跨月会跳）
/// - 月视图：整月挪，**日期会按目标月长度收口**（1 月 31 日往后挪一个月 → 2 月 28/29 日，
///   而不是被 Dart 规范化成 3 月 3 日）
DateTime shiftedFocusedDay(
  DateTime focused,
  CalendarFormat format,
  int direction,
) {
  if (direction == 0) return focused;

  if (format == CalendarFormat.week || format == CalendarFormat.twoWeeks) {
    final days = format == CalendarFormat.twoWeeks ? 14 : 7;
    return focused.add(Duration(days: days * direction));
  }

  final totalMonths = focused.year * 12 + (focused.month - 1) + direction;
  final year = totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final day = focused.day.clamp(1, _daysInMonth(year, month));
  return DateTime(year, month, day);
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
