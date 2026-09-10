import 'package:celechron/page/calendar/calendar_controller.dart';
import 'package:get/get.dart';

/// 供日期选择弹窗使用：查询某一天有哪些安排（课程 / 考试 / 日程 / 待办）。
///
/// 日历页未初始化时返回空列表，弹窗照样可用。
List<Object> calendarEventsOfDay(DateTime day) {
  if (!Get.isRegistered<CalendarController>()) return const <Object>[];
  return Get.find<CalendarController>().getMarkersForDay(day);
}
