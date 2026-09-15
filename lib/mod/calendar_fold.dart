import 'package:flutter/widgets.dart';
import 'package:table_calendar/table_calendar.dart';

/// 日程页「上滑收起日历」的手势判定 —— **纯逻辑，有单测**。
///
/// 口径（用户要求）：日程页面上滑 → 日历折成一周；滑回顶部继续下拉 → 展开整月。
///
/// 为什么不用「滑动方向」判断：手指小幅回弹时每一帧的方向会来回抖（一帧向上、
/// 下一帧向下），按方向折叠会闪。这里改成看**两个量**：
/// - 列表已经滚出去多少（[ScrollMetrics.pixels]）—— 有内容的列表滚一下就够
/// - 越界量（`OverscrollNotification.overscroll`）—— 内容不够长、列表压根滚不动
///   （比如当天只有 1 条）时，只有越界量能反映「他在往上顶」
///
/// ⚠️ 调用方必须把「不是手指直接带着动的」通知滤掉（见 [decide] 的 `fromUser`）：
/// 折叠之后列表因为日历变矮而**变高**，内容可能不再溢出，列表位置会自动弹回 0。
/// 那个自动回弹如果不滤，就会被当成「用户下拉了」，于是立刻又展开 —— 一折一展
/// 死循环。
///
/// ⚠️ 也必须在**竖向**通知上才动手：`TableCalendar` 内部是横向翻页的 `PageView`，
/// 它的通知同样会冒泡出来，而此时 `metrics.pixels` 是**横向页码偏移**，拿它判断
/// 会让日历莫名其妙折叠。
class CalendarFoldGesture {
  /// 折 / 展各要累计滑多少像素。太小会被误触（轻轻一划日历就没了），
  /// 太大则要划很久才有反应。28 差不多是「有意识地划一下」。
  static const double threshold = 28;

  /// 「已经到顶了」的容差 —— 滚动位置基本贴着 0 就算到顶。
  static const double topTolerance = 1;

  double _pullUp = 0;
  double _pullDown = 0;

  /// 一次新的触摸开始（`ScrollStartNotification`）。两个累加器都清零，
  /// 免得两次不完整的滑动凑够一个阈值。
  void startDrag() {
    _pullUp = 0;
    _pullDown = 0;
  }

  /// 拿一条滚动信息问：日历现在要不要换格式？
  ///
  /// - 返回 `CalendarFormat.week` = 折成一周
  /// - 返回 `CalendarFormat.month` = 展开整月
  /// - 返回 `null` = 这次什么都不做
  ///
  /// [pixels] 列表当前滚动位置；[delta] 本次增量（滚动通知是 `scrollDelta`，
  /// 越界通知是 `overscroll`）；[isOverscroll] 本次是不是越界通知；
  /// [fromUser] 是不是手指直接带着动的。
  CalendarFormat? decide({
    required CalendarFormat current,
    required Axis axis,
    required double pixels,
    required double delta,
    required bool isOverscroll,
    required bool fromUser,
  }) {
    if (axis != Axis.vertical || !fromUser) return null;

    if (current != CalendarFormat.week) {
      // ① 列表已经上滑出去一段 —— 有内容的列表走这条路
      if (pixels > threshold) {
        _pullUp = 0;
        return CalendarFormat.week;
      }
      // ② 内容不够长、滚不动：往上顶的越界量也算
      if (isOverscroll && delta > 0) {
        _pullUp += delta;
        if (_pullUp > threshold) {
          _pullUp = 0;
          return CalendarFormat.week;
        }
      } else if (pixels <= topTolerance) {
        _pullUp = 0;
      }
      return null;
    }

    // 已经折起来了：只有**真的回到顶部还继续往下拉**才展开。
    // 「在列表中间往下拉」不算 —— 那是想往回看几条，不是想把日历放出来。
    if (pixels > topTolerance) {
      _pullDown = 0;
      return null;
    }
    if (delta < 0) {
      _pullDown += -delta;
      if (_pullDown > threshold) {
        _pullDown = 0;
        return CalendarFormat.month;
      }
    } else {
      _pullDown = 0;
    }
    return null;
  }
}
