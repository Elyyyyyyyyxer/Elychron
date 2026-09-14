import 'dart:async';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/utils.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';

enum CalendarViewMode {
  calendar,
  schedule,

  /// 「接下来」：课程/考试/日程按开始时间、非备忘待办按提醒时间排序
  upcoming,
}

class CalendarController extends GetxController {
  final selectedDay = DateTime.now().obs;
  final focusedDay = DateTime.now().obs;
  final calendarFormat = CalendarFormat.month.obs;
  final events = <DateTime, List<Period>>{}.obs;
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');
  /// 默认进「接下来」（用户要求：打开日程页先看接下来要做什么）
  final viewMode = CalendarViewMode.upcoming.obs;

  static List<String> numToChinese = ['一', '二', '三', '四', '五', '六', '七', '八'];

  String dayDescription(DateTime day) {
    var semester = scholar.value.semesters.firstWhereOrNull(
        (e) => !day.isBefore(e.firstDay) && !day.isAfter(e.lastDay));
    if (semester == null) return '考试周/假期';

    var toFirstWeek = day.difference(semester.firstDay).inDays ~/ 7;
    if (toFirstWeek < 8) {
      return '${semester.name[9]}${numToChinese[toFirstWeek]}周';
    }
    var toLastWeek = 7 - semester.lastDay.difference(day).inDays ~/ 7;
    if (toLastWeek < 8) {
      return '${semester.name[10]}${numToChinese[toLastWeek]}周';
    }
    return '考试周/假期';
  }

  /// 「接下来」的**心跳**：定时跳一下，让倒计时与排序不会停在旧值。
  ///
  /// 背景：这一页原先没有任何定时器，`还有 N 分钟` 只在"页面碰巧重建"时才算一次。
  /// 实测出现过状态栏已经 13:16、卡片还写着「还有 24 分钟」（那是 13:01 的旧值）。
  /// 现在每 20 秒跳一次（只在看「接下来」时跳，课表/日历没有倒计时，不必跟着重建）。
  final upcomingTick = 0.obs;
  Timer? _tickTimer;

  @override
  void onInit() {
    refreshEvents();
    ever(scholar, (callback) => refreshEvents());
    _tickTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (viewMode.value == CalendarViewMode.upcoming) {
        upcomingTick.value++;
      }
    });
    super.onInit();
  }

  @override
  void onClose() {
    _tickTimer?.cancel();
    _tickTimer = null;
    super.onClose();
  }

  void refreshEvents() {
    events.clear();
    Set<DateTime> keySet = {};
    for (var element in Get.find<Rx<Scholar>>(tag: 'scholar').value.periods) {
      DateTime chop = chopDate(element.startTime);
      if (events[chop] == null) events[chop] = <Period>[];
      events[chop]!.add(element);
      keySet.add(chop);
    }
    for (var i in keySet) {
      events[i]!.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
  }

  DateTime chopDate(DateTime day) {
    return DateTime(day.year, day.month, day.day);
  }

  List<Period> getEventsForDay(DateTime day) {
    DateTime chop = chopDate(day);
    var eventsOfDay = <Period>[];
    if (events[chop] != null) {
      for (var event in events[chop]!) {
        eventsOfDay.add(event.copyWith());
      }
    }
    for (var deadline in taskList) {
      // ===== 已完成的待办不在日程页露面（用户要求）=====
      if (deadline.status == TaskStatus.completed) continue;
      if (deadline.type == TaskType.fixed ||
          deadline.type == TaskType.fixedlegacy) {
        List<Period> periods = deadline.getPeriodOfDay(dateOnly(day));
        for (var p in periods) {
          eventsOfDay.add(p);
        }
      }
    }
    eventsOfDay.sort((a, b) => a.startTime.compareTo(b.startTime));
    return eventsOfDay;
  }

  /// 当天到期的待办：**截止型与提醒型**都进日历，备忘型不进（它没有时间）。
  ///
  /// 活动型（有起止）走的是 getEventsForDay 的 Period 分支，不在这里重复出现。
  /// **已完成的也不显示** —— 日程页看的是「还要做什么」。
  List<Task> getDeadlinesForDay(DateTime day) {
    final target = dateOnly(day);
    final result = taskList
        .where((task) =>
            task.showsInCalendar &&
            !task.isEvent &&
            task.status != TaskStatus.deleted &&
            task.status != TaskStatus.completed &&
            dateOnly(task.endTime) == target)
        .toList();
    result.sort((a, b) => a.endTime.compareTo(b.endTime));
    return result;
  }

  /// 月视图上的标记：课程/考试/日程（Period）+ 当天到期的待办（Task）。
  List<Object> getMarkersForDay(DateTime day) {
    return <Object>[...getEventsForDay(day), ...getDeadlinesForDay(day)];
  }

  /// 进入课表之前是哪个面，用来「原路返回」。
  CalendarViewMode _beforeSchedule = CalendarViewMode.upcoming;

  /// 右上角那个按钮：在**课表**与「进来之前那个面」之间切换。
  ///
  /// 修的是一个实打实的方向错：原来是
  /// `viewMode == calendar ? schedule : calendar`，在「接下来」时落到 else，
  /// 于是点一下跳到**日历**——而用户点它是想看**课表**。
  ///
  /// 另外这里**不碰 [cardFace]**：翻转动画只属于「接下来 ⇄ 日历」这一对，
  /// 切课表本来就不该翻。
  /// 右上角那个按钮按下后的视图。**纯函数，便于回归测试。**
  ///
  /// 修的是一个实打实的方向错：原来是
  /// `viewMode == calendar ? schedule : calendar`，在「接下来」时落到 else，
  /// 于是点一下跳到**日历**——而用户点它是想看**课表**。
  /// 现在：不在课表 → 去课表；已在课表 → 回「进来之前那个面」。
  static CalendarViewMode toggledViewMode(
      CalendarViewMode current, CalendarViewMode beforeSchedule) {
    if (current == CalendarViewMode.schedule) return beforeSchedule;
    return CalendarViewMode.schedule;
  }

  void toggleViewMode() {
    final next = toggledViewMode(viewMode.value, _beforeSchedule);
    if (viewMode.value != CalendarViewMode.schedule) {
      _beforeSchedule = viewMode.value;
    }
    viewMode.value = next;
  }

  /// 当前是不是在看课表（右上角按钮的图标据此切换）。
  bool get isScheduleMode => viewMode.value == CalendarViewMode.schedule;

  /// 顶部那个空心圆：在「接下来」与「日历」之间翻转
  void toggleUpcoming() {
    if (viewMode.value == CalendarViewMode.upcoming) {
      viewMode.value = CalendarViewMode.calendar;
      cardFace.value = 'calendar';
    } else {
      viewMode.value = CalendarViewMode.upcoming;
      cardFace.value = 'upcoming';
    }
  }

  /// 卡片翻转的「正反面」。
  ///
  /// **只有「接下来 ⇄ 日历」这一对切换才算换面** —— 右上角那个按钮切到课表
  /// 不换面，所以不会播放翻转动画（用户反馈过：切课表也翻一下很突兀）。
  final cardFace = 'upcoming'.obs;

  Semester? getCurrentSemester() {
    final now = DateTime.now();
    return scholar.value.semesters.firstWhereOrNull((e) =>
        // 没套过校历的学期，firstDay/lastDay 是「现在」这个占位值，不能参与判断
        e.hasCalendar && !now.isBefore(e.firstDay) && !now.isAfter(e.lastDay));
  }

  /// 还没开始、但课表已经能看的学期。
  ///
  /// 开学前一天打开课表是很常见的场景（学期 9-14 开始，今天 9-13）：这时
  /// [getCurrentSemester] 是 null，课表却已经抓到了，不该给一张写着
  /// 「当前不在学期内」的白纸。
  ///
  /// ⚠️ 必须要求 [Semester.hasCalendar]：没有校历的学期 `firstDay` 返回的是
  /// 「求值那一刻的现在」，而 `now` 是先前捕获的 —— 那个值**必然晚于** `now`，
  /// 于是所有没配校历的学期都会被判成「即将开学」（实测会把 25-26 春夏选出来）。
  Semester? getUpcomingSemester() {
    final now = DateTime.now();
    final upcoming = scholar.value.semesters
        .where((e) => e.hasCalendar && e.firstDay.isAfter(now))
        .toList()
      ..sort((a, b) => a.firstDay.compareTo(b.firstDay));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// 课表实际展示的学期：优先本学期，其次即将开学的那个。
  Semester? getDisplayedSemester() =>
      getCurrentSemester() ?? getUpcomingSemester();

  /// 该学期是否还没开学（页面上据此给一句提示）。
  bool isBeforeSemester(Semester semester) =>
      DateTime.now().isBefore(semester.firstDay);

  bool isFirstHalfSemester(Semester semester) {
    final now = DateTime.now();
    final toFirstWeek = now.difference(semester.firstDay).inDays ~/ 7;
    return toFirstWeek < 8;
  }

  String getCurrentSemesterDisplayName() {
    final semester = getDisplayedSemester();
    if (semester == null) return '无学期信息';

    final isFirstHalf = isFirstHalfSemester(semester);
    final semesterName =
        '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}';
    final halfName =
        isFirstHalf ? semester.firstHalfName : semester.secondHalfName;
    // 还没开学就说清楚，免得以为课表坏了
    final prefix = isBeforeSemester(semester) ? '未开学 · ' : '';
    return '$prefix$semesterName $halfName学期';
  }
}
