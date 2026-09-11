import 'package:celechron/design/date_picker_sheet.dart';
import 'package:celechron/design/repeat_sheet.dart';
import 'package:celechron/design/task_kind_selector.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// 钉钉「其他日期」里的时间面板：截止时间 / 提醒时间 / 设置重复。
///
/// 三个子项各自弹出自己的选择器；改动直接写在 [task] 上，并通过 [onChanged]
/// 通知调用方刷新。
Future<void> showTaskTimePanel(
  BuildContext context, {
  required Task task,
  required VoidCallback onChanged,
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) =>
        _TaskTimePanel(task: task, onChanged: onChanged),
  );
}

class _TaskTimePanel extends StatefulWidget {
  final Task task;
  final VoidCallback onChanged;

  const _TaskTimePanel({required this.task, required this.onChanged});

  @override
  State<_TaskTimePanel> createState() => _TaskTimePanelState();
}

class _TaskTimePanelState extends State<_TaskTimePanel> {
  Task get _task => widget.task;

  void _notify() {
    setState(() {});
    widget.onChanged();
  }

  Future<void> _pickStartTime() async {
    final result = await showDateTimeSheet(
      context,
      initial: _task.hasTimeRange ? _task.startTime : _task.endTime,
      title: '开始时间',
    );
    if (result == null) return;
    _task.startTime = result;
    if (!_task.endTime.isAfter(_task.startTime)) {
      _task.endTime = _task.startTime.add(const Duration(hours: 1));
    }
    _task.normalizeType();
    _notify();
  }

  Future<void> _pickEndTime() async {
    final result = await showDateTimeSheet(
      context,
      initial: _task.endTime,
      title: '截止时间',
    );
    if (result == null) return;
    _task.endTime = result;
    if (_task.hasTimeRange && !_task.endTime.isAfter(_task.startTime)) {
      // 截止时间不晚于开始时间：取消时段，退化为普通待办
      _task.startTime = _task.endTime;
    }
    // 时间变了：失效的提醒时间按「该类型的锚点 − 提前量」重算。
    // 活动锚开始时间；截止与提醒锚那一刻。
    if (_task.reminderEnabled) {
      final anchor = _task.reminderAnchor;
      final target = _task.reminderTargetTime;
      if (!target.isAfter(DateTime.now()) || target.isAfter(anchor)) {
        _task.reminderTime = _defaultReminderTime();
      }
    }
    _task.normalizeType();
    _notify();
  }

  /// 默认提前量：提醒型就是那一刻（0）；其余从设置里读，默认 30 分钟。
  Duration get _defaultLead {
    if (_task.isRemind) return Duration.zero;
    if (Get.isRegistered<DatabaseHelper>(tag: 'db')) {
      final db = Get.find<DatabaseHelper>(tag: 'db');
      return Duration(minutes: db.getReminderLeadMinutes());
    }
    return const Duration(minutes: 30);
  }
  /// 按类型算默认提醒时间：锚点 − 提前量；若已过去则退回锚点本身。
  DateTime _defaultReminderTime() {
    final anchor = _task.reminderAnchor;
    final candidate = anchor.subtract(_defaultLead);
    return candidate.isAfter(DateTime.now()) ? candidate : anchor;
  }

  Future<void> _pickReminderTime() async {
    if (!_task.reminderEnabled) {
      _task.reminderEnabled = true;
      _task.reminderTime = _defaultReminderTime();
      _notify();
    }
    final result = await showDateTimeSheet(
      context,
      initial: _task.reminderTargetTime,
      title: '提醒时间',
    );
    if (result == null) return;
    _task.reminderEnabled = true;
    _task.reminderTime = result;
    _notify();
  }

  void _clearReminder() {
    _task.reminderEnabled = false;
    _task.reminderTime = null;
    _notify();
  }

  Future<void> _pickRepeat() async {
    final result =
        await showRepeatSheet(context, RepeatSetting.fromTask(_task));
    if (result == null) return;
    result.applyTo(_task);
    _notify();
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    Widget? trailing,
    bool highlight = false,
  }) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: labelColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 16, color: textColor),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                color: highlight ? CupertinoColors.systemOrange : labelColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right, size: 14, color: labelColor),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        height: 0.5,
        margin: const EdgeInsets.only(left: 32),
        color:
            CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
      );

  /// 切换时间语义：调整时间字段的逻辑在 Task.applyKind 里，三处 UI 共用。
  void _pickKind(TaskType kind) {
    if (_task.type == kind) return;
    _task.applyKind(kind);
    _notify();
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '其他日期',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ),
            // P1：四种时间语义 —— 创建/编辑时明确选择，时间输入随类型变化
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: taskKindControl(_task, _pickKind),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemGroupedBackground, context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  if (_task.isEvent) ...[
                    _row(
                      icon: CupertinoIcons.time,
                      label: '开始时间',
                      value: TimeHelper.chineseDateTime(_task.startTime),
                      onTap: _pickStartTime,
                    ),
                    _divider(),
                  ],
                  if (!_task.isRemind && !_task.isMemo) ...[
                    _row(
                      icon: CupertinoIcons.calendar,
                      label: _task.isEvent ? '结束时间' : '截止时间',
                      value: TimeHelper.chineseDateTime(_task.endTime),
                      onTap: _pickEndTime,
                    ),
                    _divider(),
                  ],
                  if (!_task.isMemo) ...[
                    _row(
                      icon: CupertinoIcons.bell,
                      label: _task.isRemind ? '提醒我' : '提醒时间',
                      value: _task.reminderEnabled
                          ? TimeHelper.chineseDateTime(_task.reminderTargetTime)
                          : '未设置',
                      highlight: _task.reminderEnabled,
                      onTap: _pickReminderTime,
                      trailing: _task.reminderEnabled
                          ? CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(28, 28),
                              onPressed: _clearReminder,
                              child: Icon(CupertinoIcons.xmark,
                                  size: 15, color: labelColor),
                            )
                          : null,
                    ),
                    _divider(),
                  ],
                  _row(
                    icon: CupertinoIcons.repeat,
                    label: '设置重复',
                    value: RepeatSetting.fromTask(_task).label,
                    onTap: _pickRepeat,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: CupertinoColors.systemBlue,
                      borderRadius: BorderRadius.circular(22),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('完成',
                          style: TextStyle(
                              fontSize: 16, color: CupertinoColors.white)),
                    ),
                  ),
                ],
              ),
            ),

            // 键盘弹出时留出高度
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ],
        ),
      ),
    );
  }
}
