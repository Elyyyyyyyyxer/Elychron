import 'package:celechron/model/period.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/calendar_events.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:table_calendar/table_calendar.dart';

/// 钉钉风格的日期选择弹窗：月历网格 + 可选的时间滚轮 + 取消/确定。
///
/// 月历上会用小圆点标出当天的课程 / 考试 / 日程 / 待办，
/// 与主日历页看到的信息保持一致。
///
/// 返回选中的日期时间；用户取消时返回 null。
Future<DateTime?> showDateTimeSheet(
  BuildContext context, {
  required DateTime initial,
  String title = '选择日期',
  bool withTime = true,
  List<Object> Function(DateTime day)? eventLoader,
}) {
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (BuildContext context) => _DateTimeSheet(
      initial: initial,
      title: title,
      withTime: withTime,
      eventLoader: eventLoader ?? calendarEventsOfDay,
    ),
  );
}

class _DateTimeSheet extends StatefulWidget {
  final DateTime initial;
  final String title;
  final bool withTime;
  final List<Object> Function(DateTime day) eventLoader;

  const _DateTimeSheet({
    required this.initial,
    required this.title,
    required this.withTime,
    required this.eventLoader,
  });

  @override
  State<_DateTimeSheet> createState() => _DateTimeSheetState();
}

class _DateTimeSheetState extends State<_DateTimeSheet> {
  late DateTime _selected;
  late DateTime _focused;
  late int _hour;
  late int _minute;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  final GlobalKey _calendarKey = GlobalKey();
  OverlayEntry? _dayPopup;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _focused = widget.initial;
    _hour = widget.initial.hour;
    _minute = widget.initial.minute;
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _dayPopup?.remove();
    _dayPopup = null;
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  /// 点某一天时，在那一天的格子下面弹一个附着的小卡片，列出当天的安排。
  void _showDayEvents(DateTime day, List<Object> events) {
    _dayPopup?.remove();
    _dayPopup = null;
    if (events.isEmpty) return;

    final box = _calendarKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    // 推算被点的那一格在屏幕上的位置
    const double headerHeight = 26;
    const double rowHeight = 42;
    final origin = box.localToGlobal(Offset.zero);
    final cellWidth = box.size.width / 7;
    final firstOfMonth = DateTime(day.year, day.month, 1);
    final gridStart =
        firstOfMonth.subtract(Duration(days: firstOfMonth.weekday % 7));
    final index = dateOnly(day).difference(dateOnly(gridStart)).inDays;
    final column = index % 7;
    final row = index ~/ 7;
    final cellRect = Rect.fromLTWH(
      origin.dx + column * cellWidth,
      origin.dy + headerHeight + row * rowHeight,
      cellWidth,
      rowHeight,
    );

    final screen = MediaQuery.of(context).size;
    const cardWidth = 268.0;
    const cardMaxHeight = 220.0;
    final left = (cellRect.center.dx - cardWidth / 2)
        .clamp(12.0, screen.width - cardWidth - 12.0);
    var top = cellRect.bottom + 6;
    if (top + cardMaxHeight > screen.height - 80) {
      top = cellRect.top - cardMaxHeight - 6;
    }
    if (top < 60) top = 60;

    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (BuildContext context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _dayPopup?.remove();
                  _dayPopup = null;
                },
                child: Container(
                  color: CupertinoColors.black.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: cardWidth,
              child: Container(
                constraints: const BoxConstraints(maxHeight: cardMaxHeight),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.systemBackground, context),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: CupertinoColors.black.withValues(alpha: 0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                      child: Text(
                        '${day.month} 月 ${day.day} 日 · ${events.length} 项安排',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context),
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 10),
                        children:
                            events.map((e) => _eventRow(context, e)).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
    _dayPopup = entry;
    overlay.insert(entry);
  }

  Widget _eventRow(BuildContext context, Object event) {
    final color = _markerColor(context, event);
    String title;
    String time;
    if (event is Period) {
      title = event.summary;
      time = TimeHelper.toHM(Duration(
          hours: event.startTime.hour, minutes: event.startTime.minute));
    } else if (event is Task) {
      title = event.summary.isEmpty ? '(未命名待办)' : event.summary;
      time =
          '截止 ${TimeHelper.toHM(Duration(hours: event.endTime.hour, minutes: event.endTime.minute))}';
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoTheme.of(context).textTheme.textStyle.color,
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondaryLabel, context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _changeMonth(int delta) {
    setState(() {
      _focused = DateTime(_focused.year, _focused.month + delta, 1);
    });
  }

  /// 月历小圆点的颜色：课程蓝、考试粉、日程橙、待办按完成状态取色。
  Color _markerColor(BuildContext context, Object event) {
    if (event is Period) {
      switch (event.type) {
        case PeriodType.classes:
          return CupertinoColors.systemBlue;
        case PeriodType.test:
          return CupertinoColors.systemPink;
        case PeriodType.user:
          return CupertinoColors.systemOrange;
        case PeriodType.virtual:
        case PeriodType.flow:
          return CupertinoColors.inactiveGray;
      }
    }
    if (event is Task) {
      return event.status == TaskStatus.completed
          ? CupertinoColors.systemGreen
          : CupertinoColors.systemOrange;
    }
    return CupertinoColors.inactiveGray;
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

    return Container(
      color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemBackground, context),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 月份标题 + 翻页
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  Text(
                    '${_focused.year}年${_focused.month}月',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    onPressed: () => _changeMonth(-1),
                    child: Icon(CupertinoIcons.chevron_left,
                        size: 20, color: labelColor),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    onPressed: () => _changeMonth(1),
                    child: Icon(CupertinoIcons.chevron_right,
                        size: 20, color: labelColor),
                  ),
                ],
              ),
            ),

            // 月历
            Padding(
              key: _calendarKey,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TableCalendar(
                locale: 'zh_CN',
                firstDay: DateTime(2020, 1, 1),
                lastDay: DateTime(2035, 12, 31),
                focusedDay: _focused,
                headerVisible: false,
                rowHeight: 42,
                daysOfWeekHeight: 26,
                startingDayOfWeek: StartingDayOfWeek.sunday,
                availableGestures: AvailableGestures.horizontalSwipe,
                eventLoader: widget.eventLoader,
                calendarBuilders: CalendarBuilders<Object>(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;
                    return Padding(
                      padding: const EdgeInsets.only(top: 26),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...events.take(4).map(
                                (e) => Container(
                                  width: 5,
                                  height: 5,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: _markerColor(context, e),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          if (events.length > 4)
                            Text('+',
                                style:
                                    TextStyle(fontSize: 8, color: labelColor)),
                        ],
                      ),
                    );
                  },
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  dowTextFormatter: (date, locale) => <String>[
                    '日',
                    '一',
                    '二',
                    '三',
                    '四',
                    '五',
                    '六'
                  ][date.weekday % 7],
                  weekdayStyle: TextStyle(fontSize: 13, color: labelColor),
                  weekendStyle: TextStyle(fontSize: 13, color: labelColor),
                ),
                selectedDayPredicate: (day) => isSameDay(_selected, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selected = DateTime(
                      selectedDay.year,
                      selectedDay.month,
                      selectedDay.day,
                      _hour,
                      _minute,
                    );
                    _focused = focusedDay;
                  });
                  _showDayEvents(selectedDay, widget.eventLoader(selectedDay));
                },
                onPageChanged: (focusedDay) {
                  setState(() => _focused = focusedDay);
                },
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  defaultTextStyle: TextStyle(fontSize: 15, color: textColor),
                  weekendTextStyle: TextStyle(fontSize: 15, color: textColor),
                  selectedDecoration: const BoxDecoration(
                    color: CupertinoColors.systemBlue,
                    shape: BoxShape.circle,
                  ),
                  selectedTextStyle: const TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  todayDecoration: BoxDecoration(
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemFill, context),
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: const TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.systemBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // 时间滚轮
            if (widget.withTime) ...[
              const SizedBox(height: 4),
              SizedBox(
                height: 110,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 90,
                      child: CupertinoPicker(
                        itemExtent: 32,
                        scrollController: _hourController,
                        onSelectedItemChanged: (value) {
                          setState(() {
                            _hour = value;
                            _selected = DateTime(
                              _selected.year,
                              _selected.month,
                              _selected.day,
                              _hour,
                              _minute,
                            );
                          });
                        },
                        children: List.generate(
                          24,
                          (index) => Center(
                            child: Text('$index',
                                style:
                                    TextStyle(fontSize: 16, color: textColor)),
                          ),
                        ),
                      ),
                    ),
                    Text('时',
                        style: TextStyle(fontSize: 15, color: labelColor)),
                    SizedBox(
                      width: 90,
                      child: CupertinoPicker(
                        itemExtent: 32,
                        looping: true,
                        scrollController: _minuteController,
                        onSelectedItemChanged: (value) {
                          setState(() {
                            _minute = value;
                            _selected = DateTime(
                              _selected.year,
                              _selected.month,
                              _selected.day,
                              _hour,
                              _minute,
                            );
                          });
                        },
                        children: List.generate(
                          60,
                          (index) => Center(
                            child: Text('$index',
                                style:
                                    TextStyle(fontSize: 16, color: textColor)),
                          ),
                        ),
                      ),
                    ),
                    Text('分',
                        style: TextStyle(fontSize: 15, color: labelColor)),
                  ],
                ),
              ),
            ],

            // 取消 / 确定
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemFill, context),
                      borderRadius: BorderRadius.circular(22),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('取消',
                          style: TextStyle(fontSize: 16, color: textColor)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: CupertinoColors.systemBlue,
                      borderRadius: BorderRadius.circular(22),
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: const Text('确定',
                          style: TextStyle(
                              fontSize: 16, color: CupertinoColors.white)),
                    ),
                  ),
                ],
              ),
            ),

            // 键盘弹出时留出高度，保证按钮不被遮挡
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
        ),
      ),
    );
  }
}
