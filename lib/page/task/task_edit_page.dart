import 'package:celechron/design/app_accent.dart';
import 'dart:async';

import 'package:celechron/design/date_picker_sheet.dart';
import 'package:celechron/design/dingtalk_menu.dart';
import 'package:celechron/design/image_preview.dart';
import 'package:celechron/design/repeat_sheet.dart';
import 'package:celechron/design/system_alarm_picker.dart';
import 'package:celechron/design/tag_picker.dart';
import 'package:celechron/design/task_priority_color.dart';
import 'package:celechron/design/task_kind_selector.dart';
import 'package:celechron/mod/ai/ai_subtasks_ui.dart';
import 'package:celechron/page/focus/focus_entry.dart';
import 'package:celechron/model/focus_engine.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/page/task/task_create_page.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:celechron/utils/attachment_helper.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:celechron/utils/task_complete.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator;
import 'package:get/get.dart';
import 'package:celechron/design/dingtalk_sheet.dart';

/// 钉钉风格的待办/日程详情页。
///
/// 保留原有契约：构造时传入 [Task]，pop 时返回编辑后的 Task（未保存则原样返回）。
class TaskEditPage extends StatefulWidget {
  final Task deadline;

  /// ===== P2：从子待办通知点进来时，高亮是哪一步 =====
  final String? highlightSubtaskUid;

  const TaskEditPage(this.deadline, {super.key, this.highlightSubtaskUid});

  @override
  State<TaskEditPage> createState() => _TaskEditPageState();
}

class _TaskEditPageState extends State<TaskEditPage> {
  late Task now;

  Timer? _ticker;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    now = widget.deadline.copyWith();
    if (now.startTime.isAfter(now.endTime)) {
      now.startTime = now.endTime;
    }
    // 「无限重复」用哨兵日期表示，不能被当成非法值清掉
    if (!isRepeatEndless(now.repeatEndsTime) &&
        dateOnly(now.repeatEndsTime).isBefore(dateOnly(now.startTime))) {
      now.repeatEndsTime = dateOnly(now.startTime);
    }
    _titleController.text = now.summary;
    _descriptionController.text = now.description;
    _locationController.text = now.location;
    // 倒计时需要每秒刷新
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 保存/校验

  void _alert(String message) {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text(message),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.of(context).pop(),
            )
          ],
        );
      },
    );
  }

  void saveAndExit() {
    if (now.hasTimeRange &&
        now.repeatType != TaskRepeatType.norepeat &&
        dateOnly(now.startTime).isAfter(dateOnly(now.repeatEndsTime))) {
      _alert('开始时间不能晚于重复截止日期');
      return;
    }

    if (now.hasTimeRange && now.repeatType != TaskRepeatType.norepeat) {
      int length = now.endTime.difference(now.startTime).inMinutes;
      if ((now.repeatType == TaskRepeatType.days &&
              length > now.repeatPeriod * 24 * 60) ||
          (now.repeatType == TaskRepeatType.month && length > 28 * 24 * 60) ||
          (now.repeatType == TaskRepeatType.year && length > 365 * 24 * 60)) {
        _alert('这个重复日程的持续时间太长');
        return;
      }
    }

    now.summary = _titleController.text;
    now.description = _descriptionController.text;
    now.location = _locationController.text;

    // 保存前归一化提醒时间：滚动日期滚轮时可能停在中间值上，
    // 这里保证提醒既不在过去、也不晚于该类型的锚点（活动=开始，截止=截止）。
    if (now.schedulesReminder) {
      _syncReminder();
    }

    now.normalizeType();
    now.updatedAt = DateTime.now();
    now.forceRefreshStatus();
    Navigator.of(context).pop(now);
  }

  void removeAndExit() {
    now.summary = _titleController.text;
    now.description = _descriptionController.text;
    now.location = _locationController.text;
    now.forceRefreshStatus();
    now.status = TaskStatus.deleted;
    Navigator.of(context).pop(now);
  }

  void exitWithoutSave() {
    now = widget.deadline.copyWith();
    Navigator.of(context).pop(now);
  }

  // ------------------------------------------------------------ 完成 / 时间

  bool get _isCompleted => now.status == TaskStatus.completed;

  /// 导航栏 ⋯ 菜单：星标 / 删除待办（钉钉风格，本地版没有「投诉」）
  Future<void> _showMoreActions() async {
    await showDingTalkMenu(
      context,
      items: [
        DingTalkMenuItem(
          label: now.starred ? '取消星标' : '星标',
          icon: now.starred ? CupertinoIcons.star_fill : CupertinoIcons.star,
          onTap: () => setState(() => now.starred = !now.starred),
        ),
        // 关键事项可以直接交给系统时钟（优先级等同起床闹钟）。
        // 放在这里而不是只藏在设置里，是因为用户找"更响的提醒"就会来这条待办的菜单。
        DingTalkMenuItem(
          label: '设为系统闹钟',
          icon: CupertinoIcons.alarm,
          onTap: () => setSystemAlarmForTask(context, now),
        ),
        DingTalkMenuItem(
          label: '删除待办',
          icon: CupertinoIcons.trash,
          destructive: true,
          onTap: removeAndExit,
        ),
      ],
    );
  }

  Future<void> _toggleCompleted() async {
    if (!_isCompleted) {
      // 有没勾完的子待办时先确认，确认后一起勾上
      if (!await confirmCompleteTask(context, now)) return;
    }
    setState(() {
      if (_isCompleted) {
        now.status = TaskStatus.running;
      } else {
        now.status = TaskStatus.completed;
      }
    });
  }

  // ---------------------------------------------------- P1：提醒锚点与提前量

  /// 默认提前量：提醒型就是那一刻（0）；其余从设置里读，默认 30 分钟。
  Duration get _defaultLead {
    if (now.isRemind) return Duration.zero;
    if (Get.isRegistered<DatabaseHelper>(tag: 'db')) {
      return Duration(
          minutes: Get.find<DatabaseHelper>(tag: 'db').getReminderLeadMinutes());
    }
    return const Duration(minutes: 30);
  }

  /// 按当前类型的锚点算默认提醒时间：锚点 − 提前量；若已过去则退回锚点本身。
  DateTime _defaultReminderTime() {
    final anchor = now.reminderAnchor;
    final candidate = anchor.subtract(_defaultLead);
    return candidate.isAfter(DateTime.now()) ? candidate : anchor;
  }

  /// 时间或类型变了之后，把失效的提醒时间按新锚点重算一次。
  ///
  /// 活动锚「开始」、截止锚「截止」、提醒型就是那一刻；备忘不调度。
  void _syncReminder() {
    if (!now.schedulesReminder) return;
    final anchor = now.reminderAnchor;
    final target = now.reminderTargetTime;
    if (target.isAfter(anchor) || !target.isAfter(DateTime.now())) {
      now.reminderTime = now.isRemind ? null : _defaultReminderTime();
    }
  }

  Future<void> _pickEndTime() async {
    final result = await showDateTimeSheet(
      context,
      initial: now.endTime,
      title: now.endTimeLabel,
    );
    if (result == null || !mounted) return;
    setState(() {
      now.endTime = result;
      if (now.isEvent && now.startTime.isAfter(now.endTime)) {
        now.startTime = now.endTime;
      }
      _syncReminder();
    });
  }

  /// 提醒型的「那一刻」：直接改 endTime（= 锚点），提醒时间继续跟随锚点。
  Future<void> _pickRemindMoment() async {
    final result = await showDateTimeSheet(
      context,
      initial: now.endTime,
      title: '提醒时刻',
    );
    if (result == null || !mounted) return;
    setState(() {
      now.endTime = result;
      now.startTime = result;
      now.reminderTime = null;
    });
  }

  Future<void> _pickStartTime() async {
    final result = await showDateTimeSheet(
      context,
      initial: now.startTime,
      title: '开始时间',
    );
    if (result == null || !mounted) return;
    setState(() {
      now.startTime = result;
      if (now.endTime.isBefore(now.startTime)) {
        now.endTime = now.startTime;
      }
      _syncReminder();
    });
  }

  Future<void> _pickReminderTime() async {
    final result = await showDateTimeSheet(
      context,
      initial: now.reminderTargetTime,
      title: '提醒时间',
    );
    if (result == null || !mounted) return;
    setState(() {
      now.reminderEnabled = true;
      now.reminderTime = result;
    });
  }

  Future<void> _pickRepeat() async {
    final result = await showRepeatSheet(context, RepeatSetting.fromTask(now));
    if (result == null || !mounted) return;
    setState(() => result.applyTo(now));
  }

  void _toggleReminder() {
    if (!now.reminderEnabled) {
      setState(() {
        now.reminderEnabled = true;
        // 活动锚开始、截止锚截止，各自再提前「默认提前量」
        now.reminderTime = now.isRemind ? null : _defaultReminderTime();
      });
    } else {
      _pickReminderTime();
    }
  }

  void _clearReminder() {
    setState(() {
      now.reminderEnabled = false;
      now.reminderTime = null;
    });
  }

  Future<void> _pickPriority() async {
    // ===== MOD: 换成钉钉风格弹层；优先级保留各自的颜色语义 =====
    final picked = await showDingTalkSheet<TaskPriority>(
      context: context,
      title: '设置优先级',
      current: now.priority,
      options: [
        for (final priority in TaskPriority.values)
          DingTalkSheetOption(
            label: taskPriorityName[priority]!,
            value: priority,
            color: taskPriorityColor(priority),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => now.priority = picked);
  }

  // --------------------------------------------------------------- 子待办

  /// 点「添加子待办」：先弹小窗口选「选择现有待办 / 新建子待办」
  /// 添加子待办：钉钉风格弹窗，三种方式（选现有的 / 新建 / 让 AI 拆）
  Future<void> _addSubtask() async {
    String? action;
    await showDingTalkMenu(
      context,
      title: '添加子待办',
      message: '还没想好怎么拆？可以让 AI 按这条待办的内容给出几条能做的小步骤。',
      items: [
        DingTalkMenuItem(
          label: '选择现有待办',
          icon: CupertinoIcons.list_bullet,
          onTap: () => action = 'existing',
        ),
        DingTalkMenuItem(
          label: '新建子待办',
          icon: CupertinoIcons.add,
          onTap: () => action = 'new',
        ),
        DingTalkMenuItem(
          label: 'AI 拆成子待办',
          icon: Icons.auto_awesome,
          onTap: () => action = 'ai',
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'new') {
      await _createNewSubtask();
    } else if (action == 'ai') {
      await runAiSubtasks(context, now, onChanged: () => setState(() {}));
    } else {
      await _pickExistingTaskAsSubtask();
    }
  }

  /// 新建子待办：用「和新建待办一样」的窗口
  Future<void> _createNewSubtask() async {
    final draft = Task(
      endTime: now.endTime,
      startTime: now.endTime,
      repeatEndsTime: dateOnly(now.endTime),
    );
    draft.reset();
    draft.endTime = now.endTime;
    draft.startTime = now.endTime;
    draft.repeatEndsTime = dateOnly(now.endTime);

    final res = await showCupertinoModalPopup<Task>(
      context: context,
      builder: (BuildContext context) => TaskCreatePage(
        draft,
        pageTitle: '新建子待办',
        heightFactor: 0.86,
      ),
    );
    if (res == null || !mounted) return;
    setState(() => now.subtasks.add(SubTask.fromTask(res)));
  }

  /// 选择现有待办：列出其它待办，选中的内容会成为一条子待办
  Future<void> _pickExistingTaskAsSubtask() async {
    final controller = Get.find<TaskController>();
    final candidates = controller.taskList
        .where((t) =>
            t.uid != now.uid &&
            t.type != TaskType.fixedlegacy &&
            t.status != TaskStatus.deleted)
        .toList()
      ..sort((a, b) => a.endTime.compareTo(b.endTime));
    if (candidates.isEmpty) {
      _alert('还没有其它待办可以选');
      return;
    }

    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

    final picked = await showCupertinoModalPopup<Task>(
      context: context,
      builder: (BuildContext context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemBackground, context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Row(
                  children: [
                    const SizedBox(width: 64),
                    const Spacer(),
                    const Text('选择现有待办',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(64, 44),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: candidates.length,
                  separatorBuilder: (context, index) => Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 20),
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.separator, context),
                  ),
                  itemBuilder: (context, index) {
                    final task = candidates[index];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(task),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.summary.isEmpty ? '(未命名待办)' : task.summary,
                              style: TextStyle(fontSize: 16, color: textColor),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '截止 ${TimeHelper.chineseDateTime(task.endTime)}',
                              style: TextStyle(fontSize: 13, color: labelColor),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => now.subtasks.add(SubTask.fromTask(picked)));
  }

  /// 点已有子待办：同样用新建窗口来编辑
  Future<void> _editSubtask(SubTask subtask) async {
    final res = await showCupertinoModalPopup<Task>(
      context: context,
      builder: (BuildContext context) => TaskCreatePage(
        subtask.toTask(),
        pageTitle: '编辑子待办',
        confirmLabel: '保存',
        heightFactor: 0.86,
      ),
    );
    if (res == null || !mounted) return;
    setState(() => subtask.applyFromTask(res));
  }

  // 专注时长显示统一走 focus_engine 的 focusHuman（那份有单测）

  /// 从任务列表里取同 uid 的那条（详情页手上是副本，要拿它的最新字段）
  Task? _taskFromList(String uid) {
    try {
      final list = Get.find<RxList<Task>>(tag: 'taskList');
      for (final task in list) {
        if (task.uid == uid) return task;
      }
    } catch (_) {}
    return null;
  }

  /// 子待办自己的时间已经过去、又没勾完 —— 标红（行程子待办过期标红）。
  bool _subtaskOverdue(SubTask subtask) {
    final end = subtask.endTime;
    return !subtask.done && end != null && end.isBefore(DateTime.now());
  }

  // ------------------------------------------------- P2：行程型时间轴

  /// 只要**有一步带时间**，这一组子待办就按「行程表」画。
  ///
  /// 清单型（写论文 → 查文献 / 写提纲）没有时间，仍然走老的两行式列表。
  bool get _isItinerary => now.subtasks.any((s) => s.hasTime);

  static String _hm(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  /// 时间列上的文字：日期单独一行（不是今天才显示），下面一行是 `14:30-17:30`。
  ///
  /// 分成两行是为了不让 `18:00-18:10` 在窄列里被折断成 `18:00-18:1 / 0`。
  ({String date, String time}) _timelineLabels(SubTask sub) {
    final anchor = sub.anchorTime;
    if (anchor == null) return (date: '', time: '');
    final now_ = DateTime.now();
    final today = DateTime(now_.year, now_.month, now_.day);
    final day = DateTime(anchor.year, anchor.month, anchor.day);
    final date = day == today ? '' : '${anchor.month}-${anchor.day}';
    final time = sub.isSpan
        ? '${_hm(sub.startTime!)}-${_hm(sub.endTime!)}'
        : _hm(anchor);
    return (date: date, time: time);
  }

  /// 这一步的提醒说明：`会在 17:40 提醒` / `13:50 已提醒`。
  String _timelineReminderHint(SubTask sub, DateTime current) {
    final when = sub.reminderAt(_defaultLead.inMinutes);
    if (when == null) return '';
    if (when.isAfter(current)) return '会在 ${_hm(when)} 提醒';
    return '${_hm(when)} 已提醒过';
  }

  /// 时间轴的显示顺序：**清单类（没有时间的）放最上面** —— 它们是「先要做完的
  /// 准备」，然后才是按时间排好的行程步骤。
  ///
  /// 只影响显示，不改存储顺序（用户没手动排序时保持他原来的顺序）。
  List<SubTask> _timelineOrder() {
    final timeless = now.subtasks.where((s) => !s.hasTime).toList();
    final timed = now.subtasks
        .where((s) => s.hasTime && s.anchorTime != null)
        .toList()
      ..sort((a, b) => a.anchorTime!.compareTo(b.anchorTime!));
    // 理论上不会有「有时间但算不出时刻」的，真有也别让它消失
    final rest = now.subtasks
        .where((s) => s.hasTime && s.anchorTime == null)
        .toList();
    return <SubTask>[...timeless, ...timed, ...rest];
  }

  /// 行程型子待办：时间列 + 竖线圆点 + 内容（进行中高亮、已过去未完成标红）
  List<Widget> _buildSubtaskTimeline(BuildContext context) {
    final current = DateTime.now();
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color ??
        CupertinoColors.label;
    final separator =
        CupertinoDynamicColor.resolve(CupertinoColors.separator, context);

    final ordered = _timelineOrder();
    final widgets = <Widget>[];
    var itineraryHeaderAdded = false;

    for (var i = 0; i < ordered.length; i++) {
      final sub = ordered[i];
      final plain = !sub.hasTime; // 清单类：不画时间列与连线
      final ongoing = sub.isOngoingAt(current);
      final missed = sub.isMissedAt(current);
      final flagged = widget.highlightSubtaskUid == sub.uid;
      // 连线只在「连续的行程步骤之间」画
      final hasNextTimed =
          i < ordered.length - 1 && ordered[i + 1].hasTime;
      final isLast = !hasNextTimed;

      // 第一段行程步骤之前插一句「行程」，让「上面是清单、下面是行程」看得懂
      if (!plain && !itineraryHeaderAdded) {
        itineraryHeaderAdded = true;
        if (ordered.any((s) => !s.hasTime)) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Row(
                children: [
                  Icon(CupertinoIcons.time, size: 13, color: labelColor),
                  const SizedBox(width: 4),
                  Text('行程',
                      style: TextStyle(fontSize: 12, color: labelColor)),
                ],
              ),
            ),
          );
        }
      }
      final accent = ongoing
          ? CupertinoColors.systemBlue
          : (missed ? CupertinoColors.systemRed : labelColor);

      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  sub.title.isEmpty ? '(未命名子待办)' : sub.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: ongoing ? FontWeight.w600 : FontWeight.w400,
                    color: sub.done
                        ? labelColor
                        : (missed ? CupertinoColors.systemRed : textColor),
                    decoration:
                        sub.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (ongoing)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '进行中',
                    style: TextStyle(
                        fontSize: 11, color: CupertinoColors.systemBlue),
                  ),
                ),
            ],
          ),
          if (sub.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                sub.description,
                style: TextStyle(fontSize: 12, color: labelColor),
              ),
            ),
          if (sub.location.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Icon(CupertinoIcons.location_solid,
                      size: 12, color: accent),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      sub.location,
                      style: TextStyle(fontSize: 12, color: accent),
                    ),
                  ),
                ],
              ),
            ),
          if (!sub.done && _timelineReminderHint(sub, current).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Icon(
                    sub.reminderAt(_defaultLead.inMinutes)!.isAfter(current)
                        ? CupertinoIcons.bell
                        : CupertinoIcons.bell_slash,
                    size: 12,
                    color: labelColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _timelineReminderHint(sub, current),
                    style: TextStyle(fontSize: 11, color: labelColor),
                  ),
                ],
              ),
            ),
        ],
      );

      widgets.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 时间列（清单类留白，保持内容对齐）
              SizedBox(
                width: 74,
                child: plain
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 1, right: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_timelineLabels(sub).date.isNotEmpty)
                              Text(
                                _timelineLabels(sub).date,
                                style:
                                    TextStyle(fontSize: 10, color: labelColor),
                              ),
                            Text(
                              _timelineLabels(sub).time,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: ongoing
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              // 竖线 + 圆点（清单类不画）
              SizedBox(
                width: 18,
                child: plain
                    ? null
                    : Column(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: sub.done
                                  ? CupertinoColors.systemGreen
                                  : (ongoing
                                      ? CupertinoColors.systemBlue
                                      : separator),
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Container(width: 1.5, color: separator),
                            ),
                        ],
                      ),
              ),
              const SizedBox(width: 8),
              // 内容 + 打钩
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: ongoing || flagged
                        ? CupertinoColors.systemBlue.withValues(alpha: 0.08)
                        : CupertinoColors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _editSubtask(sub),
                          child: content,
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(32, 32),
                        onPressed: () =>
                            setState(() => sub.done = !sub.done),
                        child: Icon(
                          sub.done
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 20,
                          color: sub.done
                              ? CupertinoColors.systemGreen
                              : CupertinoDynamicColor.resolve(
                                  CupertinoColors.tertiaryLabel, context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  /// 子待办行下方的概要信息（截止 / 优先级 / 标签 / 附件 / 地点）
  String _subtaskMeta(SubTask subtask) {
    final parts = <String>[];
    if (subtask.endTime != null) {
      parts.add('截止 ${TimeHelper.chineseDateTime(subtask.endTime!)}');
    }
    if (subtask.priority != TaskPriority.normal) {
      parts.add(taskPriorityName[subtask.priority]!);
    }
    if (subtask.tags.isNotEmpty) parts.add(subtask.tags.join('/'));
    if (subtask.attachments.isNotEmpty) {
      parts.add('附件 ${subtask.attachments.length}');
    }
    if (subtask.location.isNotEmpty) parts.add(subtask.location);
    return parts.join(' · ');
  }

  // ------------------------------------------------------------------ 标签

  Future<void> _addTag() async {
    final tag = await pickTagFromLibrary(context, selected: now.tags);
    if (tag == null || !mounted) return;
    setState(() => now.tags.add(tag));
  }

  Widget _tagChip(String tag) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemGroupedBackground, context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag,
            style: TextStyle(
              fontSize: 14,
              color:
                  CupertinoDynamicColor.resolve(CupertinoColors.label, context),
            ),
          ),
          const SizedBox(width: 4),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(24, 24),
            onPressed: () => setState(() => now.tags.remove(tag)),
            child: Icon(
              CupertinoIcons.xmark,
              size: 13,
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondaryLabel, context),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 附件

  Future<void> _pickAttachments() async {
    try {
      final added = await pickAttachments();
      if (added.isEmpty || !mounted) return;
      setState(() => now.attachments.addAll(added));
    } catch (e) {
      if (mounted) _alert('选择文件失败：$e');
    }
  }

  Future<void> _openAttachment(TaskAttachment attachment) async {
    if (isImageFile(attachment.path)) {
      await showImagePreview(context,
          path: attachment.path, name: attachment.name);
      return;
    }
    try {
      await openAttachment(context, attachment);
    } catch (e) {
      if (mounted) _alert('打开附件失败：$e');
    }
  }

  // ---------------------------------------------------------------- 评论

  void _addComment() {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;
    setState(() {
      now.comments.add(TaskComment(content: content, time: DateTime.now()));
      _commentController.clear();
    });
  }

  // ------------------------------------------------------------------ 样式

  Widget _card({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.secondarySystemGroupedBackground, context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 18, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.secondaryLabel, context),
        ),
      ),
    );
  }

  Widget _iconRow({
    IconData? icon,
    Widget? leading,
    required Widget child,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading ??
              Icon(
                icon,
                size: 20,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiaryLabel, context),
              ),
          const SizedBox(width: 12),
          Expanded(child: child),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }

  Widget _chip({
    required Widget child,
    VoidCallback? onTap,
  }) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemGroupedBackground, context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color:
              CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
          width: 0.5,
        ),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }

  Widget _divider() {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 32),
      color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: exitWithoutSave,
          child: const Icon(CupertinoIcons.xmark),
        ),
        middle: const Text('待办详情'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _showMoreActions,
              child: const Icon(CupertinoIcons.ellipsis_circle,
                  semanticLabel: '更多'),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: saveAndExit,
              child: const Icon(CupertinoIcons.check_mark),
            ),
          ],
        ),
        border: null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 40),
          children: [
            // 完成待办 + 开始专注
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _chip(
                    onTap: _toggleCompleted,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isCompleted
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 18,
                          color: _isCompleted
                              ? CupertinoColors.systemGreen
                              : CupertinoColors.systemBlue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isCompleted ? '已完成' : '完成待办',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _isCompleted
                                ? CupertinoColors.systemGreen
                                : CupertinoColors.systemBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // ===== P3：拿这条待办去专注（时长会累加进 timeSpent）=====
                  _chip(
                    onTap: () async {
                      await startFocusFor(context, task: now);
                      if (!mounted) return;
                      // 专注时长是累加到**任务列表里那条**上的，详情页手上这份是副本。
                      // 不把新值取回来，用户接着按「√」保存就会用旧的 timeSpent
                      // 把刚记下的专注时长覆盖掉。
                      final fresh = _taskFromList(now.uid);
                      setState(() {
                        if (fresh != null) now.timeSpent = fresh.timeSpent;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.timer,
                            size: 18, color: AppAccent.primary),
                        const SizedBox(width: 6),
                        Text(
                          now.timeSpent > Duration.zero
                              ? '开始专注 · 已记 ${focusHuman(now.timeSpent)}'
                              : '开始专注',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppAccent.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: CupertinoTextField(
                controller: _titleController,
                placeholder: '待办标题',
                padding: EdgeInsets.zero,
                decoration: const BoxDecoration(),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
                placeholderStyle: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.placeholderText, context),
                ),
                maxLines: null,
                onChanged: (value) => now.summary = value,
              ),
            ),

            const SizedBox(height: 8),

            // 描述
            _card(
              children: [
                _iconRow(
                  icon: CupertinoIcons.doc_text,
                  child: CupertinoTextField(
                    controller: _descriptionController,
                    placeholder: '添加描述',
                    padding: EdgeInsets.zero,
                    decoration: const BoxDecoration(),
                    maxLines: null,
                    minLines: 1,
                    style: TextStyle(fontSize: 16, color: textColor),
                    onChanged: (value) => now.description = value,
                  ),
                ),
              ],
            ),

            // ===== P1：时间类型 + 时间行（全部随类型变化）=====
            _card(
              children: [
                taskKindControl(now, (kind) {
                  setState(() {
                    now.applyKind(kind);
                    _syncReminder();
                  });
                }),
                if (!now.isMemo) ...[
                  _divider(),
                  // 「结束 / 截止」：活动与截止型才有；提醒型的时间由下面那行负责
                  if (!now.isRemind)
                    _iconRow(
                      icon: CupertinoIcons.time,
                      child: _chip(
                        onTap: _pickEndTime,
                        child: Text(
                          '${TimeHelper.chineseDateTime(now.endTime)} ${now.isEvent ? '结束' : '截止'}',
                          style: TextStyle(fontSize: 15, color: textColor),
                        ),
                      ),
                    ),
                  // 提醒时刻：活动的开始前、截止的截止前、提醒型的那一瞬
                  _iconRow(
                    icon: now.reminderEnabled
                        ? CupertinoIcons.bell_fill
                        : CupertinoIcons.bell,
                    child: now.reminderEnabled
                        ? GestureDetector(
                            onTap: now.isRemind
                                ? _pickRemindMoment
                                : _pickReminderTime,
                            child: Text(
                              now.isRemind
                                  ? '到点提醒：${TimeHelper.chineseDateTime(now.reminderTargetTime)}'
                                  : '提醒：${TimeHelper.chineseDateTime(now.reminderTargetTime)}',
                              style: const TextStyle(
                                fontSize: 15,
                                color: CupertinoColors.systemOrange,
                              ),
                            ),
                          )
                        : GestureDetector(
                            onTap: _toggleReminder,
                            child: Text(
                              '添加提醒',
                              style: TextStyle(fontSize: 15, color: labelColor),
                            ),
                          ),
                    trailing: now.reminderEnabled
                        ? CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(32, 32),
                            onPressed: _clearReminder,
                            child: Icon(CupertinoIcons.xmark,
                                size: 16, color: labelColor),
                          )
                        : null,
                  ),
                  // 开始时间：只有活动型才有「时段」
                  if (now.isEvent) ...[
                    _divider(),
                    _iconRow(
                      icon: CupertinoIcons.time_solid,
                      onTap: _pickStartTime,
                      child: Text(
                        now.hasTimeRange
                            ? '开始于 ${TimeHelper.chineseDateTime(now.startTime)}'
                            : '设置开始时间',
                        style: TextStyle(fontSize: 15, color: textColor),
                      ),
                    ),
                  ],
                ],
              ],
            ),

            // 时间状态（备忘型不显示；只有截止型过期才标红）
            if (now.timeStatus != null)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 2),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.hourglass,
                      size: 14,
                      color: now.timeStatus!.urgent
                          ? CupertinoColors.systemRed
                          : labelColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      now.timeStatus!.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: now.timeStatus!.urgent
                            ? CupertinoColors.systemRed
                            : labelColor,
                      ),
                    ),
                  ],
                ),
              ),

            // 优先级
            _card(
              children: [
                _iconRow(
                  icon: CupertinoIcons.flag,
                  child: _chip(
                    onTap: _pickPriority,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '优先级：${taskPriorityName[now.priority]}',
                          style: TextStyle(
                            fontSize: 15,
                            color: taskPriorityColor(now.priority),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 14,
                          color: labelColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 重复
            _card(
              children: [
                _iconRow(
                  icon: CupertinoIcons.repeat,
                  child: _chip(
                    onTap: _pickRepeat,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '设置重复：${RepeatSetting.fromTask(now).label}',
                          style: TextStyle(fontSize: 15, color: textColor),
                        ),
                        const SizedBox(width: 4),
                        Icon(CupertinoIcons.chevron_right,
                            size: 14, color: labelColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 标签
            _card(
              children: [
                _iconRow(
                  icon: CupertinoIcons.tag,
                  child: now.tags.isEmpty
                      ? GestureDetector(
                          onTap: _addTag,
                          child: Text('添加待办标签',
                              style:
                                  TextStyle(fontSize: 16, color: labelColor)),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ...now.tags.map((tag) => _tagChip(tag)),
                            GestureDetector(
                              onTap: _addTag,
                              child: const Icon(
                                CupertinoIcons.add_circled,
                                size: 22,
                                color: CupertinoColors.systemBlue,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),

            // 子待办
            _card(
              children: [
                _iconRow(
                  icon: CupertinoIcons.list_bullet,
                  child: Row(
                    children: [
                      Text('子待办',
                          style: TextStyle(fontSize: 16, color: textColor)),
                      const Spacer(),
                      if (now.subtasks.isNotEmpty)
                        Text(
                          '${now.subtaskDoneCount}/${now.subtasks.length}',
                          style: TextStyle(fontSize: 14, color: labelColor),
                        ),
                    ],
                  ),
                ),
                // ===== P1：活动已结束还在「我已处理」里，没做完的子待办红字点出来 =====
                if (now.hasUnfinishedSubtasks)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, bottom: 6),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.exclamationmark_circle,
                            size: 14, color: CupertinoColors.systemRed),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '活动已结束，还有 ${now.subtasks.length - now.subtaskDoneCount} 个子待办没做完',
                            style: const TextStyle(
                                fontSize: 13, color: CupertinoColors.systemRed),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (now.subtasks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, bottom: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: now.subtaskProgress,
                        minHeight: 4,
                        color: CupertinoColors.systemBlue,
                        backgroundColor: CupertinoDynamicColor.resolve(
                            CupertinoColors.separator, context),
                      ),
                    ),
                  ),
                // ===== P2：行程型画成时间轴，清单型保持老样子 =====
                if (_isItinerary) ...[
                  _divider(),
                  const SizedBox(height: 10),
                  ..._buildSubtaskTimeline(context),
                ] else
                  ...now.subtasks.map((subtask) {
                  return Column(
                    children: [
                      _divider(),
                      Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Row(
                          children: [
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(32, 40),
                              onPressed: () {
                                setState(() => subtask.done = !subtask.done);
                              },
                              child: Icon(
                                subtask.done
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                size: 20,
                                color: subtask.done
                                    ? CupertinoColors.systemGreen
                                    : CupertinoDynamicColor.resolve(
                                        CupertinoColors.tertiaryLabel, context),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _editSubtask(subtask),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subtask.title.isEmpty
                                            ? '(未命名子待办)'
                                            : subtask.title,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: subtask.done
                                              ? labelColor
                                              : (_subtaskOverdue(subtask)
                                                  ? CupertinoColors.systemRed
                                                  : textColor),
                                          decoration: subtask.done
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      if (_subtaskMeta(subtask).isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            _subtaskMeta(subtask),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _subtaskOverdue(subtask)
                                                  ? CupertinoColors.systemRed
                                                  : labelColor,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(32, 40),
                              onPressed: () {
                                setState(() => now.subtasks.remove(subtask));
                              },
                              child: Icon(
                                CupertinoIcons.xmark,
                                size: 16,
                                color: labelColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
                _divider(),
                _iconRow(
                  icon: CupertinoIcons.add,
                  onTap: _addSubtask,
                  child: Text(
                    '添加子待办',
                    style: TextStyle(fontSize: 16, color: labelColor),
                  ),
                ),
              ],
            ),

            // 附件
            _card(
              children: [
                ...now.attachments.map((attachment) {
                  final thumbnail = attachmentThumbnail(attachment.path);
                  return Column(
                    children: [
                      _iconRow(
                        icon:
                            thumbnail == null ? CupertinoIcons.paperclip : null,
                        leading: thumbnail,
                        onTap: () => _openAttachment(attachment),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                attachment.name,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(fontSize: 15, color: textColor),
                              ),
                            ),
                            if (formatFileSize(attachment.size).isNotEmpty)
                              Text(
                                formatFileSize(attachment.size),
                                style:
                                    TextStyle(fontSize: 12, color: labelColor),
                              ),
                          ],
                        ),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(32, 32),
                          onPressed: () {
                            setState(() => now.attachments.remove(attachment));
                          },
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 16,
                            color: labelColor,
                          ),
                        ),
                      ),
                      _divider(),
                    ],
                  );
                }),
                _iconRow(
                  icon: CupertinoIcons.paperclip,
                  onTap: _pickAttachments,
                  child: Text(
                    '添加附件',
                    style: TextStyle(fontSize: 16, color: labelColor),
                  ),
                ),
              ],
            ),

            // 地点
            _card(
              children: [
                _iconRow(
                  icon: CupertinoIcons.location,
                  child: CupertinoTextField(
                    controller: _locationController,
                    placeholder: '添加地点',
                    padding: EdgeInsets.zero,
                    decoration: const BoxDecoration(),
                    style: TextStyle(fontSize: 16, color: textColor),
                    onChanged: (value) => now.location = value,
                  ),
                ),
              ],
            ),

            // 评论 / 备注
            _sectionTitle('评论 / 备注'),
            _card(
              children: [
                if (now.comments.isEmpty)
                  _iconRow(
                    icon: CupertinoIcons.chat_bubble,
                    child: Text('还没有评论',
                        style: TextStyle(fontSize: 15, color: labelColor)),
                  ),
                ...now.comments.map((comment) {
                  return Column(
                    children: [
                      _iconRow(
                        icon: CupertinoIcons.chat_bubble_text,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(comment.content,
                                style:
                                    TextStyle(fontSize: 15, color: textColor)),
                            const SizedBox(height: 4),
                            Text(
                              TimeHelper.chineseDateTime(comment.time),
                              style: TextStyle(fontSize: 12, color: labelColor),
                            ),
                          ],
                        ),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(32, 32),
                          onPressed: () {
                            setState(() => now.comments.remove(comment));
                          },
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 16,
                            color: labelColor,
                          ),
                        ),
                      ),
                      _divider(),
                    ],
                  );
                }),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.pencil,
                        size: 20,
                        color: CupertinoColors.systemBlue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CupertinoTextField(
                          controller: _commentController,
                          placeholder: '写下备注或评论',
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: const BoxDecoration(),
                          style: TextStyle(fontSize: 15, color: textColor),
                          onSubmitted: (_) => _addComment(),
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 36),
                        onPressed: _addComment,
                        child: const Icon(
                          CupertinoIcons.arrow_up_circle_fill,
                          size: 24,
                          color: CupertinoColors.systemBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 删除
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: CupertinoButton(
                onPressed: removeAndExit,
                child: const Text(
                  '删除待办',
                  style: TextStyle(color: CupertinoColors.systemPink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
