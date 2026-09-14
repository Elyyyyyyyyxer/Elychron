import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/card_flip.dart';
import 'package:celechron/design/custom_decoration.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/design/task_priority_color.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_create_page.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/page/task/task_edit_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/utils/task_complete.dart';
import 'package:celechron/utils/utils.dart';

import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/page/scholar/course_detail/course_detail_view.dart';
import 'package:celechron/model/upcoming.dart';
import 'package:celechron/page/calendar/schedule_view.dart';
import 'package:celechron/page/calendar/upcoming_view.dart';
import 'calendar_controller.dart';

class CalendarPage extends StatelessWidget {
  CalendarPage({super.key});
  final _calendarController = Get.put(CalendarController());
  final _taskController = Get.put(TaskController());
  final deadlineList = Get.find<RxList<Task>>(tag: 'taskList');

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        // ===== 整页当成一张卡片翻：顶栏 + 内容一起转 =====
        // 只有「接下来 ⇄ 日历」换面才翻（faceKey 只在 toggleUpcoming 里变），
        // 右上角切课表不换面，所以不会莫名其妙翻一下。
        child: Obx(
          () => CardFlipSwitcher(
            flipKey: _calendarController.cardFace.value,
            face: _calendarController.viewMode.value,
            // 每一面都由「面」这个参数算出来 —— 旧面不会跟着 controller 变
            faceBuilder: (Object face) => Obx(
              () => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context, face as CalendarViewMode),
                  Expanded(
                      child: _body(context, face as CalendarViewMode)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 顶栏：标题 + 两侧按钮 + 居中的「接下来」翻转开关。
  ///
  /// 从 build() 里搬出来的（纯搬家，逻辑一行没改）—— 目的是让 build() 短到
  /// 可以在外面安全地套一层「整页翻转」容器。
  Widget _header(BuildContext context, CalendarViewMode mode) {
    return Stack(
      alignment: Alignment.center,
        children: [
          SubtitleRow(
        subtitle: switch (mode) {
          // 「接下来」模式下别显示学期/月份那串信息，直接说这是什么页面
          CalendarViewMode.upcoming => '接下来',
          CalendarViewMode.calendar =>
            '${_calendarController.focusedDay.value.year} 年 ${_calendarController.focusedDay.value.month} 月',
          CalendarViewMode.schedule =>
            _calendarController.getCurrentSemesterDisplayName(),
        },
        right: Row(
          children: [
            if (mode ==
                CalendarViewMode.calendar) ...[
              CupertinoButton(
                padding: EdgeInsets.zero,
                child: const Icon(
                  CupertinoIcons.add_circled,
                  semanticLabel: 'Add',
                ),
                onPressed: () async {
                  await newDeadline(
                    context,
                    time: DateTime(
                      _calendarController.selectedDay.value.year,
                      _calendarController.selectedDay.value.month,
                      _calendarController.selectedDay.value.day,
                      DateTime.now().hour,
                      DateTime.now().minute,
                    ),
                  );
                  _taskController.updateDeadlineList();
                  _taskController.taskList.refresh();
                },
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                child: Text('今天',
                    style: TextStyle(
                        fontSize: 18,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.systemBlue, context))),
                onPressed: () {
                  _calendarController.focusedDay.value = DateTime.now();
                  _calendarController.selectedDay.value =
                      DateTime.now();
                },
              ),
            ],
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: Icon(
                // 不在课表时：点它去看课表（列表图标）；
                // 已在课表时：点它回到进来之前的那个面（返回图标）。
                _calendarController.isScheduleMode
                    ? CupertinoIcons.chevron_back
                    : CupertinoIcons.list_bullet,
                semanticLabel:
                    _calendarController.isScheduleMode ? '返回' : '查看课表',
              ),
              onPressed: () {
                _calendarController.toggleViewMode();
              },
            ),
          ],
        ),
        padHorizontal: 18,
      ),
          // ===== 顶部居中的小空心圆：点它翻转「接下来」⇄ 日历 =====
          // （空心态 = 正在看「接下来」；圆心有点 = 正在看日历，点回「接下来」）
          //
          // 课表模式下**不显示**它：那个圆只管「接下来 ⇄ 日历」这对翻转，
          // 留在课表上既没用，又会压在标题文字上（「未开学 · 26-27秋冬 秋学期」这种长标题必撞）。
          if (mode != CalendarViewMode.schedule)
            Positioned(
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _calendarController.toggleUpcoming,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 1.6,
                          color: mode ==
                                  CalendarViewMode.upcoming
                              ? AppAccent.primary
                              : CupertinoDynamicColor.resolve(
                                  CupertinoColors.secondaryLabel, context),
                        ),
                      ),
                      child: mode ==
                              CalendarViewMode.calendar
                          ? Center(
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.secondaryLabel,
                                      context),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
    );
  }

  /// 页面主体：课表 / 接下来 / 日历 三种视图之一（同样是从 build() 搬出来的）
  Widget _body(BuildContext context, CalendarViewMode mode) {
    final Widget body;
          if (mode == CalendarViewMode.schedule) {
            body = ScheduleView(controller: _calendarController);
          } else if (mode == CalendarViewMode.upcoming) {
            // ===== 「接下来」：最近的一条大字号 =====
            body = UpcomingView(
              items: _upcomingItems(),
              onAddTask: () => newDeadline(context, time: DateTime.now()),
            );
          } else {
            body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                    bottom: 5, left: 12, right: 12),
                child: TableCalendar(
                  locale: 'zh_CN',
                  firstDay: DateTime.utc(2022, 9, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  rowHeight: 48.0,
                  daysOfWeekHeight: 20.0,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  daysOfWeekStyle: DaysOfWeekStyle(
                    dowTextFormatter: (date, locale) => <String>[
                      '',
                      '一',
                      '二',
                      '三',
                      '四',
                      '五',
                      '六',
                      '日'
                    ][date.weekday],
                  ),
                  availableGestures: AvailableGestures.all,
                  availableCalendarFormats: const {
                    CalendarFormat.month: '显示整月',
                    CalendarFormat.week: '显示一周',
                  },
                  headerVisible: false,
                  focusedDay: _calendarController.focusedDay.value,
                  selectedDayPredicate: (day) {
                    return isSameDay(
                        _calendarController.selectedDay.value, day);
                  },
                  calendarFormat:
                      _calendarController.calendarFormat.value,
                  onPageChanged: (focusedDay) {
                    _calendarController.focusedDay.value = focusedDay;
                  },
                  onDaySelected: (selectedDay, focusedDay) {
                    _calendarController.focusedDay.value = focusedDay;
                    _calendarController.selectedDay.value = selectedDay;
                    _calendarController.focusedDay.refresh();
                  },
                  onFormatChanged: (format) {
                    _calendarController.calendarFormat.value = format;
                  },
                  eventLoader: (day) {
                    // 课程 / 考试 / 日程 / 待办 都参与月视图标记
                    return _calendarController.getMarkersForDay(day);
                  },
                  calendarStyle: CalendarStyle(
                    markersAnchor: -0.1,
                    markersMaxCount: 10,
                    selectedDecoration: BoxDecoration(
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.activeBlue
                              .withValues(alpha: 0.5),
                          context),
                      shape: BoxShape.circle,
                    ),
                    selectedTextStyle:
                        CupertinoTheme.of(context).textTheme.textStyle,
                    todayDecoration: BoxDecoration(
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.inactiveGray
                              .withValues(alpha: 0.5),
                          context),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle:
                        CupertinoTheme.of(context).textTheme.textStyle,
                    defaultTextStyle:
                        CupertinoTheme.of(context).textTheme.textStyle,
                  ),
                  calendarBuilders: const CalendarBuilders(
                    singleMarkerBuilder: singleMarkerBuilder,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Obx(
                () => SubSubtitleRow(
                    padHorizontal: 24,
                    subtitle: _calendarController.dayDescription(
                        _calendarController.selectedDay.value
                            .copyWith(isUtc: false)),
                    right: _calendarController
                            .scholar.value.specialDates
                            .containsKey(_calendarController
                                .selectedDay.value
                                .copyWith(isUtc: false))
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: CustomCupertinoDynamicColors
                                        .okGreen.darkColor,
                                    width: 1),
                                borderRadius:
                                    BorderRadius.circular(10)),
                            child: Text(
                              _calendarController
                                      .scholar.value.specialDates[
                                  _calendarController.selectedDay.value
                                      .copyWith(isUtc: false)]!,
                              style: TextStyle(
                                  color: CustomCupertinoDynamicColors
                                      .okGreen.darkColor,
                                  fontSize: 12),
                            ),
                          )
                        : null),
              ),
              Expanded(
                child: Obx(
                  () => ListView(
                    children: _buildDayEntries(context),
                  ),
                ),
              ),
            ],
          );
          }
    return body;
  }


  Future<void> newDeadline(context, {required DateTime time}) async {
    Task? deadline = Task(
      endTime: time,
      startTime: time,
      repeatEndsTime: time,
    );
    deadline.reset();
    deadline.startTime = time.copyWith();
    deadline.endTime = time.copyWith();
    deadline.repeatEndsTime = time.copyWith();
    deadline.status = TaskStatus.running;
    Task? res = await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return TaskCreatePage(deadline);
      },
    );
    if (res != null && res.status != TaskStatus.deleted) {
      _taskController.taskList.add(res);
      _taskController.updateDeadlineList();
      _taskController.updateDeadlineListTime();
      _taskController.taskList.refresh();
    }
  }

  Future<void> showCardDialog(BuildContext context, Task deadline) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text(deadline.summary),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (deadline.repeatType != TaskRepeatType.norepeat) ...[
                  const Text(
                    '重复日程，接下来的时段：',
                  ),
                ],
                Text(
                  '开始于 ${toStringHumanReadable(deadline.startTime)}',
                ),
                Text(
                  '结束于 ${toStringHumanReadable(deadline.endTime)}',
                ),
                if (deadline.location.isNotEmpty) ...[
                  Text(
                    '地点：${deadline.location}',
                  ),
                ],
                if (deadline.description.isNotEmpty) ...[
                  Text(
                    '说明：${deadline.description}',
                  ),
                ],
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
            if (deadline.type == TaskType.fixed)
              CupertinoDialogAction(
                onPressed: () async {
                  Navigator.of(context).pop();
                  Task res = await showCupertinoModalPopup(
                        context: context,
                        builder: (BuildContext context) {
                          return TaskEditPage(deadline);
                        },
                      ) ??
                      deadline;
                  deadline.copy(res);
                  _taskController.updateDeadlineList();
                  _taskController.updateDeadlineListTime();
                  _taskController.taskList.refresh();
                },
                child: const Text('编辑'),
              ),
            if (deadline.type == TaskType.fixedlegacy)
              CupertinoDialogAction(
                onPressed: () async {
                  Navigator.of(context).pop();
                  deadline.status = TaskStatus.deleted;
                  _taskController.updateDeadlineList();
                  _taskController.taskList.refresh();
                },
                child: const Text('删除'),
              ),
          ],
        );
      },
    );
  }

  /// 某一天的列表：课程 / 考试 / 日程（Period）+ 当天到期的待办（Task），按时间排序。
  List<Widget> _buildDayEntries(BuildContext context) {
    final day = _calendarController.selectedDay.value;
    final entries = <MapEntry<DateTime, Widget>>[];

    for (final period in _calendarController.getEventsForDay(day)) {
      entries.add(MapEntry(period.startTime, createCard(context, period)));
    }
    for (final task in _calendarController.getDeadlinesForDay(day)) {
      entries.add(MapEntry(task.endTime, createDeadlineCard(context, task)));
    }

    entries.sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
            child: e.value,
          ),
        )
        .toList();
  }

  /// 找出某个 Period 对应的任务（用于打钩完成）。
  Task? _taskOfPeriod(Period period) {
    if (period.type != PeriodType.user) return null;
    return deadlineList.firstWhereOrNull((task) => task.uid == period.fromUid);
  }

  Widget _taskCheckbox(BuildContext context, Task task) {
    final done = task.status == TaskStatus.completed;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(40, 40),
      onPressed: () => _toggleTaskDone(context, task),
      child: Icon(
        done ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
        size: 22,
        color: done
            ? CupertinoColors.systemGreen
            : CupertinoDynamicColor.resolve(
                CupertinoColors.tertiaryLabel, context),
      ),
    );
  }

  /// 直接在日历里打钩完成 / 取消完成。
  Future<void> _toggleTaskDone(BuildContext context, Task task) async {
    if (task.status == TaskStatus.completed) {
      task.status = TaskStatus.running;
    } else {
      // 有没勾完的子待办时先确认，确认后一起勾上
      if (!await confirmCompleteTask(context, task)) return;
      task.status = TaskStatus.completed;
    }
    _taskController.updateDeadlineList();
    _taskController.updateDeadlineListTime();
    _taskController.taskList.refresh();
  }

  /// 待办（DDL）在日历里的卡片：打钩 + 标题 + 截止时间 + 子待办进度。
  Widget createDeadlineCard(BuildContext context, Task task) {
    final done = task.status == TaskStatus.completed;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return RoundRectangleCard(
      onTap: () async {
        Task? res = await Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (BuildContext context) => TaskEditPage(task),
          ),
        );
        if (res != null) {
          if (res.status == TaskStatus.deleted) {
            task.status = TaskStatus.deleted;
          } else {
            task.copy(res);
          }
        }
        _taskController.updateDeadlineList();
        _taskController.updateDeadlineListTime();
        _taskController.taskList.refresh();
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8),
        child: Row(
          children: [
            _taskCheckbox(context, task),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12.0,
                        height: 12.0,
                        decoration: customDecoration(
                          color: UidColors.colorFromUid(task.uid),
                          shape: periodTypeShape[PeriodType.user]!,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          task.summary.isEmpty ? '(未命名待办)' : task.summary,
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .textStyle
                              .copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                overflow: TextOverflow.ellipsis,
                                decoration:
                                    done ? TextDecoration.lineThrough : null,
                              ),
                        ),
                      ),
                      if (task.priority != TaskPriority.normal)
                        Icon(CupertinoIcons.flag_fill,
                            size: 14, color: taskPriorityColor(task.priority)),
                    ],
                  ),
                  const SizedBox(height: 4.0),
                  // ===== P1：时间行随类型变化（备忘不显示；只有截止型过期才标红）=====
                  if (_taskTimeLine(task) != null)
                    Text(
                      _taskTimeLine(task)!,
                      style: TextStyle(
                        fontSize: 14,
                        color: task.timeStatus?.urgent == true
                            ? CupertinoColors.systemRed
                            : labelColor,
                      ),
                    ),
                  if (task.location.isNotEmpty)
                    Text(
                      '地点 ${task.location}',
                      style: TextStyle(fontSize: 14, color: labelColor),
                    ),
                  if (task.subtasks.isNotEmpty)
                    Text(
                      '子待办 ${task.subtaskDoneCount}/${task.subtasks.length}',
                      style: TextStyle(fontSize: 14, color: labelColor),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 日程页卡片上的那一行时间（四类语义各说各的）。
  ///
  /// 备忘返回 null = 这一行不显示（它本来就没有时间）。
  String? _taskTimeLine(Task task) {
    if (task.isEvent) {
      return '${toStringHumanReadable(task.startTime)} - ${toStringHumanReadable(task.endTime)}';
    }
    if (task.isRemind) {
      return '提醒 ${toStringHumanReadable(task.reminderTargetTime)}';
    }
    if (task.isMemo) return null;
    return '截止 ${toStringHumanReadable(task.endTime)}${task.isOverdue ? ' - 已过期' : ''}';
  }

  Widget createCard(context, Period period) {
    return RoundRectangleCard(
      onTap:
          (period.type == PeriodType.classes || period.type == PeriodType.test)
              ? () async => Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute(
                      builder: (context) =>
                          CourseDetailPage(courseId: period.fromUid)))
              : (period.type == PeriodType.user
                  ? (() async {
                      Task? deadline;
                      for (var x in deadlineList) {
                        if (x.uid == period.fromUid) {
                          deadline = x;
                          break;
                        }
                      }
                      if (deadline != null) {
                        showCardDialog(context, deadline);
                      }
                    })
                  : null),
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8),
        child: Row(
          children: [
            if (period.type == PeriodType.user)
              () {
                final task = _taskOfPeriod(period);
                if (task == null) return const SizedBox.shrink();
                return _taskCheckbox(context, task);
              }(),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12.0,
                        height: 12.0,
                        decoration: customDecoration(
                          color: period.type == PeriodType.classes
                              ? (TimeColors.colorFromHour(
                                  period.startTime.hour))
                              : (period.type == PeriodType.test
                                  ? CupertinoColors.systemPink
                                  : (period.type == PeriodType.user &&
                                          period.fromUid != null
                                      ? UidColors.colorFromUid(
                                          period.fromFromUid ?? period.fromUid)
                                      : CupertinoColors.inactiveGray)),
                          shape: periodTypeShape[period.type]!,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          period.summary,
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .textStyle
                              .copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                overflow: TextOverflow.ellipsis,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4.0),
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.time_solid,
                        size: 14,
                        color: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .color!
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 6.0),
                      Expanded(
                        child: Text(
                          '时间：${period.friendlyTimeStartDayBased}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .color!
                                .withValues(alpha: 0.75),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (period.location.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.location_solid,
                          size: 14,
                          color: CupertinoTheme.of(context)
                              .textTheme
                              .textStyle
                              .color!
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 6.0),
                        Expanded(
                          child: Text(
                            '地点：${period.location}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .color!
                                  .withValues(alpha: 0.75),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 14,
                color: CupertinoTheme.of(context)
                    .textTheme
                    .textStyle
                    .color!
                    .withValues(alpha: 0.5))
          ],
        ),
      ),
    );
  }

  /// 「接下来」的条目：课程/考试/日程按开始时间、非备忘待办按提醒时间。
  /// 排序与过滤逻辑在 `model/upcoming.dart`（有单测），这里只负责把数据喂进去。
  List<UpcomingItem> _upcomingItems() {
    // 读一下心跳：让包住这一层的 Obx 每 20 秒重算一次。
    // 否则「还有 N 分钟」会停在页面上次重建时的旧值（实测差过一刻钟）。
    _calendarController.upcomingTick.value;
    return buildUpcoming(
      periods: _calendarController.scholar.value.periods,
      tasks: deadlineList.toList(),
      now: DateTime.now(),
    );
  }
  static Widget singleMarkerBuilder(context, day, Object event) {
    if (event is Task) {
      return Container(
        width: 4.5,
        height: 4.5,
        margin: const EdgeInsets.symmetric(horizontal: 0.3),
        decoration: customDecoration(
          color: event.status == TaskStatus.completed
              ? CupertinoColors.systemGreen
              : UidColors.colorFromUid(event.uid),
          shape: periodTypeShape[PeriodType.user]!,
        ),
      );
    }
    if (event is! Period) return const SizedBox.shrink();
    final Period period = event;
    if (period.type == PeriodType.virtual) {
      return const SizedBox.shrink();
    }

    Color color = CupertinoColors.systemPink;
    if (period.type == PeriodType.classes) {
      color = TimeColors.colorFromHour(period.startTime.hour);
    } else if (period.type == PeriodType.user) {
      color = UidColors.colorFromUid(period.fromFromUid ?? period.fromUid);
    }

    double size = 4.5;

    if (period.type == PeriodType.test) {
      size = 6;
    }

    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 0.3),
      decoration: customDecoration(
        color: color,
        shape: periodTypeShape[period.type]!,
      ),
    );
  }
}
