import 'dart:async';

import 'package:celechron/design/date_picker_sheet.dart';
import 'package:celechron/design/dingtalk_menu.dart';
import 'package:celechron/design/image_preview.dart';
import 'package:celechron/design/repeat_sheet.dart';
import 'package:celechron/design/tag_picker.dart';
import 'package:celechron/design/task_priority_color.dart';
import 'package:celechron/mod/ai/ai_subtasks_ui.dart';
import 'package:celechron/model/task.dart';
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

/// 钉钉风格的待办/日程详情页。
///
/// 保留原有契约：构造时传入 [Task]，pop 时返回编辑后的 Task（未保存则原样返回）。
class TaskEditPage extends StatefulWidget {
  final Task deadline;
  const TaskEditPage(this.deadline, {super.key});

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
    // 这里保证提醒既不在过去、也不晚于截止时间。
    if (now.reminderEnabled) {
      final target = now.reminderTargetTime;
      if (!target.isAfter(DateTime.now()) || target.isAfter(now.endTime)) {
        final candidate = now.endTime.subtract(const Duration(minutes: 30));
        now.reminderTime =
            candidate.isAfter(DateTime.now()) ? candidate : now.endTime;
      }
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
          label: 'AI 拆成子待办',
          icon: Icons.auto_awesome,
          onTap: () => runAiSubtasks(
            context,
            now,
            onChanged: () => setState(() {}),
          ),
        ),
        DingTalkMenuItem(
          label: now.starred ? '取消星标' : '星标',
          icon: now.starred ? CupertinoIcons.star_fill : CupertinoIcons.star,
          onTap: () => setState(() => now.starred = !now.starred),
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
        now.timeSpent = const Duration(minutes: 0);
        now.status = TaskStatus.running;
      } else {
        now.status = TaskStatus.completed;
      }
    });
  }

  String _formatRemaining(Duration d) {
    final expired = d.isNegative;
    d = expired ? -d : d;
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    String text;
    if (days > 0) {
      text = '$days 天 $hours 小时';
    } else if (hours > 0) {
      text = '$hours 小时 $minutes 分钟';
    } else if (minutes > 0) {
      text = '$minutes 分钟';
    } else {
      text = '不到 1 分钟';
    }
    return expired ? '已超时 $text' : '剩 $text';
  }

  Future<void> _pickEndTime() async {
    final result = await showDateTimeSheet(
      context,
      initial: now.endTime,
      title: now.type == TaskType.deadline ? '截止时间' : '结束时间',
    );
    if (result == null || !mounted) return;
    setState(() {
      now.endTime = result;
      if (now.type == TaskType.fixed && now.startTime.isAfter(now.endTime)) {
        now.startTime = now.endTime;
      }
      // 截止时间变了，如果原来的提醒时间已失效（已过或晚于新的截止），
      // 就按“截止前 30 分钟”重新推算。
      if (now.reminderEnabled) {
        final target = now.reminderTargetTime;
        if (!target.isAfter(DateTime.now()) || target.isAfter(now.endTime)) {
          final candidate = now.endTime.subtract(const Duration(minutes: 30));
          now.reminderTime =
              candidate.isAfter(DateTime.now()) ? candidate : now.endTime;
        }
      }
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
        final candidate = now.endTime.subtract(const Duration(minutes: 30));
        now.reminderEnabled = true;
        now.reminderTime =
            candidate.isAfter(DateTime.now()) ? candidate : now.endTime;
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
    await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: const Text('设置优先级'),
          actions: TaskPriority.values.map((priority) {
            return CupertinoActionSheetAction(
              onPressed: () {
                setState(() => now.priority = priority);
                Navigator.of(context).pop();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    now.priority == priority
                        ? CupertinoIcons.checkmark_alt
                        : null,
                    size: 18,
                    color: taskPriorityColor(priority),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    taskPriorityName[priority]!,
                    style: TextStyle(color: taskPriorityColor(priority)),
                  ),
                ],
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------- 子待办

  /// 点「添加子待办」：先弹小窗口选「选择现有待办 / 新建子待办」
  Future<void> _addSubtask() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('添加子待办'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('existing'),
            child: const Text('选择现有待办'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('new'),
            child: const Text('新建子待办'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'new') {
      await _createNewSubtask();
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
            // 完成待办
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _chip(
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

            // 截止时间 + 提醒
            _card(
              children: [
                _iconRow(
                  icon: CupertinoIcons.time,
                  child: _chip(
                    onTap: _pickEndTime,
                    child: Text(
                      '${TimeHelper.chineseDateTime(now.endTime)} ${now.type == TaskType.deadline ? '截止' : '结束'}',
                      style: TextStyle(fontSize: 15, color: textColor),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(32, 32),
                        onPressed: _toggleReminder,
                        child: Icon(
                          now.reminderEnabled
                              ? CupertinoIcons.bell_fill
                              : CupertinoIcons.bell,
                          size: 20,
                          color: now.reminderEnabled
                              ? CupertinoColors.systemOrange
                              : labelColor,
                        ),
                      ),
                      if (now.reminderEnabled)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(32, 32),
                          onPressed: _clearReminder,
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 18,
                            color: labelColor,
                          ),
                        ),
                    ],
                  ),
                ),
                if (now.reminderEnabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, bottom: 10),
                    child: GestureDetector(
                      onTap: _pickReminderTime,
                      child: Text(
                        '提醒时间：${TimeHelper.chineseDateTime(now.reminderTargetTime)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemOrange,
                        ),
                      ),
                    ),
                  ),
                _divider(),
                _iconRow(
                  icon: CupertinoIcons.time_solid,
                  onTap: _pickStartTime,
                  child: Text(
                    now.hasTimeRange
                        ? '开始于 ${TimeHelper.chineseDateTime(now.startTime)}'
                        : '设置开始时间（可选）',
                    style: TextStyle(
                      fontSize: 15,
                      color: now.hasTimeRange ? textColor : labelColor,
                    ),
                  ),
                  trailing: now.hasTimeRange
                      ? CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(32, 32),
                          onPressed: () => setState(() {
                            now.startTime = now.endTime;
                            now.normalizeType();
                          }),
                          child: Icon(CupertinoIcons.xmark,
                              size: 16, color: labelColor),
                        )
                      : null,
                ),
              ],
            ),

            // 倒计时
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 2),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.hourglass,
                    size: 14,
                    color: now.remainingTime.isNegative
                        ? CupertinoColors.systemRed
                        : labelColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '距截止${_formatRemaining(now.remainingTime)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: now.remainingTime.isNegative
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
                                              : textColor,
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
                                              color: labelColor,
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
