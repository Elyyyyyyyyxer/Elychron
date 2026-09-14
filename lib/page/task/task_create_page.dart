import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/date_picker_sheet.dart';
import 'package:celechron/design/repeat_sheet.dart';
import 'package:celechron/design/image_preview.dart';
import 'package:celechron/design/tag_picker.dart';
import 'package:celechron/design/task_priority_color.dart';
import 'package:celechron/design/task_kind_selector.dart';
import 'package:celechron/design/task_time_panel.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/attachment_helper.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:celechron/mod/ai/ai_compose_sheet.dart';
import 'package:celechron/mod/ai/ai_task_draft.dart';
import 'package:celechron/design/dingtalk_sheet.dart';

/// 钉钉风格的「新建待办」页。
///
/// 待办、子待办都用它来新建/编辑，只是标题与确认按钮文案不同；
/// 传了 [heightFactor] 时不再占满屏幕，上方留出一条空隙（子待办用）。
class TaskCreatePage extends StatefulWidget {
  final Task initial;
  final String pageTitle;
  final String confirmLabel;
  final double? heightFactor;

  const TaskCreatePage(
    this.initial, {
    super.key,
    this.pageTitle = '新建待办',
    this.confirmLabel = '新建',
    this.heightFactor,
  });

  @override
  State<TaskCreatePage> createState() => _TaskCreatePageState();
}

class _TaskCreatePageState extends State<TaskCreatePage> {
  late Task now;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    now = widget.initial.copyWith();

    // 把传入的内容回填到输入框（分享进来 / 编辑子待办时会预填）
    _titleController.text = now.summary;
    _descriptionController.text = now.description;
    _locationController.text = now.location;

    // 新建待办默认截止到今天 23:59，对应「今天」这个默认选中的快捷日期
    final today = DateTime.now();
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59);
    if (now.endTime.isBefore(endOfDay) && now.summary.isEmpty) {
      now.endTime = endOfDay;
      now.startTime = endOfDay;
      now.repeatEndsTime = dateOnly(endOfDay);
    }

    // 标题变化时刷新「新建」按钮的可用状态
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _canCreate => _titleController.text.trim().isNotEmpty;

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

  // ------------------------------------------------------------------ 保存

  void _saveAndExit() {
    if (!_canCreate) return;

    now.summary = _titleController.text.trim();
    now.description = _descriptionController.text;
    now.normalizeType();
    now.createdAt ??= DateTime.now();
    now.updatedAt = DateTime.now();
    now.forceRefreshStatus();
    Navigator.of(context).pop(now);
  }

  void _exitWithoutSave() => Navigator.of(context).pop();

  // ------------------------------------------------------------ 时间

  /// 快捷日期：今天 / 明天 / 其他日期
  void _applyQuickDate(DateTime day) {
    setState(() {
      final newEnd = DateTime(day.year, day.month, day.day, 23, 59);
      if (now.hasTimeRange) {
        final length = now.endTime.difference(now.startTime);
        now.endTime = newEnd;
        now.startTime = newEnd.subtract(length);
      } else {
        now.endTime = newEnd;
        now.startTime = newEnd;
      }
      if (now.repeatType == TaskRepeatType.norepeat) {
        now.repeatEndsTime = dateOnly(newEnd);
      }
    });
  }

  /// 子待办时间列上的文字：时段写成 `14:30-17:30`，单时刻只写 `14:20`
  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _subtaskTimeLabel(SubTask sub) {
    if (sub.isSpan) {
      return '${_hm(sub.startTime!)}-${_hm(sub.endTime!)}';
    }
    final anchor = sub.anchorTime;
    return anchor == null ? '' : _hm(anchor);
  }

  /// 改某一步的时间：原本是「时段」的保留时长，原本是「时刻」的还是一个时刻
  Future<void> _editSubtaskTime(int index) async {
    final sub = now.subtasks[index];
    final picked = await showDateTimeSheet(
      context,
      initial: sub.anchorTime ?? now.endTime,
      title: '这一步的时间',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (sub.isSpan) {
        final length = sub.endTime!.difference(sub.startTime!);
        sub.startTime = picked;
        sub.endTime = picked.add(length);
      } else {
        // 单时刻：与 SubTask.fromTask 的约定保持一致，只放 endTime
        sub.startTime = null;
        sub.endTime = picked;
      }
    });
  }

  // ---------------------------------------------------------------- 其他日期

  /// 「其他日期」面板：截止时间 / 提醒时间 / 设置重复 都收在这里。
  Future<void> _showOtherDatePanel() async {
    await showTaskTimePanel(
      context,
      task: now,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  /// 快捷日期下方的只读摘要，让人一眼看到当前的时间设置（随类型变化）。
  String _timeSummary() {
    final parts = <String>[];
    if (now.isMemo) {
      return '备忘：不设时间、不提醒、永不逾期，也不进日历';
    }
    if (now.isRemind) {
      parts.add('${TimeHelper.chineseDateTime(now.endTime)} 提醒');
    } else if (now.isEvent) {
      if (now.hasTimeRange) {
        parts.add('${TimeHelper.chineseDateTime(now.startTime)} 开始');
        parts.add('${TimeHelper.chineseDateTime(now.endTime)} 结束');
      } else {
        parts.add('${TimeHelper.chineseDateTime(now.endTime)} 开始');
      }
    } else {
      parts.add('截止 ${TimeHelper.chineseDateTime(now.endTime)}');
    }
    final repeat = RepeatSetting.fromTask(now).label;
    if (repeat != '不重复') parts.add(repeat);
    // 提醒型上面那句已经是「… 提醒」，不再重复一遍
    if (now.schedulesReminder && !now.isRemind) {
      parts.add('提醒 ${TimeHelper.chineseDateTime(now.reminderTargetTime)}');
    }
    return parts.join(' · ');
  }

  // ---------------------------------------------------------------- 优先级

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

  // ------------------------------------------------------------------ 标签

  Future<void> _addTag() async {
    final tag = await pickTagFromLibrary(context, selected: now.tags);
    if (tag == null || !mounted) return;
    setState(() => now.tags.add(tag));
  }

  // ------------------------------------------------------------------ 附件

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

  Widget _dateBadge(DateTime date, Color color) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '${date.day}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// 快捷日期胶囊：今天/明天带日期数字徽标，其他日期用日历图标。
  Widget _quickDateChip({
    required String label,
    DateTime? date,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = selected
        ? CupertinoColors.systemBlue
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.tertiarySystemGroupedBackground, context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? CupertinoColors.systemBlue
                : CupertinoDynamicColor.resolve(
                    CupertinoColors.separator, context),
            width: selected ? 1 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (date == null)
              Icon(CupertinoIcons.calendar, size: 18, color: color)
            else
              _dateBadge(date, color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 14, color: color)),
          ],
        ),
      ),
    );
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
          Text(tag,
              style: TextStyle(
                  fontSize: 14,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label, context))),
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

  // ------------------------------------------------------------------ build

  // ===== MOD: AI 整理成待办 =====
  // AI 只产出受限草稿，由 AiTaskDraft 逐字段校验后再 applyTo，绝不直接吃模型 JSON
  Future<void> _runAiCompose() async {
    final title = _titleController.text.trim();
    final seed = title.length > 25 ? title : _descriptionController.text;
    final draft = await showAiComposeSheet(context, initialText: seed);
    if (draft == null || !mounted) return;
    setState(() {
      draft.applyTo(now);
      _titleController.text = now.summary;
      _descriptionController.text = now.description;
      _locationController.text = now.location;
    });
    if (draft.warnings.isNotEmpty) {
      _alert('已填入，但有几处我替你改了：\n\n${draft.warnings.join('\n')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    final now_ = DateTime.now();
    final today = DateTime(now_.year, now_.month, now_.day);
    final tomorrow = today.add(const Duration(days: 1));
    final endDate = dateOnly(now.endTime);

    final page = CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _exitWithoutSave,
          child: const Icon(CupertinoIcons.xmark),
        ),
        middle: Text(widget.pageTitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== MOD: AI 整理入口 =====
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _runAiCompose,
              child: const Icon(Icons.auto_awesome, size: 21),
            ),
            const SizedBox(width: 14),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _canCreate ? _saveAndExit : null,
              child: Text(
                widget.confirmLabel,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        border: null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 40),
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: CupertinoTextField(
                controller: _titleController,
                placeholder: '写下你的待办事项',
                padding: EdgeInsets.zero,
                decoration: const BoxDecoration(),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
                placeholderStyle: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.placeholderText, context),
                ),
                maxLines: null,
                onChanged: (value) => now.summary = value,
              ),
            ),

            const SizedBox(height: 10),

            // ===== P1：时间类型（活动 / 截止 / 提醒 / 备忘）=====
            // 放在最上面，是因为它决定了下面所有时间输入长什么样。
            _card(
              children: [
                taskKindControl(now, (kind) {
                  setState(() => now.applyKind(kind));
                }),
              ],
            ),

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

            // 执行人
            _card(
              children: [
                _iconRow(
                  icon: CupertinoIcons.person,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _chip(
                      onTap: () => _alert('本地版没有协作成员，任务默认由你执行'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: CupertinoColors.systemBlue,
                              shape: BoxShape.circle,
                            ),
                            child: const Text(
                              '我',
                              style: TextStyle(
                                  fontSize: 12, color: CupertinoColors.white),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('执行',
                              style: TextStyle(fontSize: 15, color: textColor)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // 快捷日期（备忘型不设时间，整块隐藏）
            if (!now.isMemo)
              _card(
                children: [
                  _iconRow(
                    icon: CupertinoIcons.calendar,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _quickDateChip(
                            label: '今天',
                            date: today,
                            selected: endDate == today,
                            onTap: () => _applyQuickDate(today),
                          ),
                          const SizedBox(width: 8),
                          _quickDateChip(
                            label: '明天',
                            date: tomorrow,
                            selected: endDate == tomorrow,
                            onTap: () => _applyQuickDate(tomorrow),
                          ),
                          const SizedBox(width: 8),
                          _quickDateChip(
                            label: '其他日期',
                            selected: endDate != today && endDate != tomorrow,
                            onTap: _showOtherDatePanel,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 32, bottom: 10),
                    child: Text(
                      _timeSummary(),
                      style: TextStyle(fontSize: 13, color: labelColor),
                    ),
                  ),
                ],
              ),

            // 优先级
            _card(
              children: [
                _iconRow(
                  icon: CupertinoIcons.flag,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _chip(
                      onTap: _pickPriority,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '优先级：${taskPriorityName[now.priority]}',
                            style: TextStyle(
                                fontSize: 15,
                                color: taskPriorityColor(now.priority)),
                          ),
                          const SizedBox(width: 4),
                          Icon(CupertinoIcons.chevron_right,
                              size: 14, color: labelColor),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ===== 子待办（AI 填进来的步骤在这里就能看/改，不用先建完再点进详情页）=====
            if (now.subtasks.isNotEmpty)
              _card(
                children: [
                  _iconRow(
                    icon: CupertinoIcons.list_bullet,
                    child: Row(
                      children: [
                        Text('子待办',
                            style: TextStyle(fontSize: 16, color: textColor)),
                        const Spacer(),
                        Text('${now.subtasks.length} 步',
                            style:
                                TextStyle(fontSize: 14, color: labelColor)),
                      ],
                    ),
                  ),
                  ...now.subtasks.asMap().entries.map((entry) {
                    final index = entry.key;
                    final sub = entry.value;
                    final meta = <String>[
                      if (sub.location.isNotEmpty) sub.location,
                      if (sub.description.isNotEmpty) sub.description,
                    ];
                    return Column(
                      children: [
                        _divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              // 点时间改这一步（原本是时段的保留时长）
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _editSubtaskTime(index),
                                child: SizedBox(
                                  width: 76,
                                  child: Text(
                                    sub.hasTime
                                        ? _subtaskTimeLabel(sub)
                                        : '＋时间',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: sub.hasTime
                                          ? AppAccent.primary
                                          : labelColor,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sub.title.isEmpty ? '(未命名步骤)' : sub.title,
                                      style: TextStyle(
                                          fontSize: 15, color: textColor),
                                    ),
                                    if (meta.isNotEmpty)
                                      Text(
                                        meta.join(' · '),
                                        style: TextStyle(
                                            fontSize: 12, color: labelColor),
                                      ),
                                  ],
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(28, 28),
                                onPressed: () =>
                                    setState(() => now.subtasks.removeAt(index)),
                                child: Icon(CupertinoIcons.xmark_circle_fill,
                                    size: 18,
                                    color: CupertinoDynamicColor.resolve(
                                        CupertinoColors.tertiaryLabel,
                                        context)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
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
                            ...now.tags.map(_tagChip),
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
                          child: Icon(CupertinoIcons.xmark,
                              size: 16, color: labelColor),
                        ),
                      ),
                      _divider(),
                    ],
                  );
                }),
                _iconRow(
                  icon: CupertinoIcons.paperclip,
                  onTap: _pickAttachments,
                  child: Text('添加附件',
                      style: TextStyle(fontSize: 16, color: labelColor)),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // 子待办用：不占满屏幕，上方留出一条空隙，顶部圆角
    if (widget.heightFactor == null) return page;
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: widget.heightFactor,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: page,
        ),
      ),
    );
  }
}
