import 'package:celechron/design/date_picker_sheet.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:celechron/design/dingtalk_sheet.dart';

enum RepeatUnit { day, week, month, year }

const Map<RepeatUnit, String> repeatUnitName = {
  RepeatUnit.day: '天',
  RepeatUnit.week: '周',
  RepeatUnit.month: '月',
  RepeatUnit.year: '年',
};

/// 重复规则的界面表示：把 Task 里的 repeatType / repeatPeriod / repeatEndsTime
/// 组合成「每天重复 / 每 2 周重复 / 每周工作日 …」这种可读形式。
class RepeatSetting {
  final TaskRepeatType type;
  final int period;
  final bool endless;
  final DateTime endsDate;

  RepeatSetting({
    required this.type,
    this.period = 1,
    this.endless = true,
    DateTime? endsDate,
  }) : endsDate = endsDate ?? kRepeatEndlessDate;

  factory RepeatSetting.fromTask(Task task) => RepeatSetting(
        type: task.repeatType,
        period: task.repeatPeriod,
        endless: isRepeatEndless(task.repeatEndsTime),
        endsDate: task.repeatEndsTime,
      );

  void applyTo(Task task) {
    task.repeatType = type;
    task.repeatPeriod = period;
    task.repeatEndsTime = endless ? kRepeatEndlessDate : dateOnly(endsDate);
  }

  /// 自定义重复里的「每 N 单位」——把 period 还原成 N + 单位。
  RepeatUnit get unit {
    switch (type) {
      case TaskRepeatType.month:
        return RepeatUnit.month;
      case TaskRepeatType.year:
        return RepeatUnit.year;
      case TaskRepeatType.days:
        if (period > 1 && period % 7 == 0) return RepeatUnit.week;
        return RepeatUnit.day;
      default:
        return RepeatUnit.day;
    }
  }

  int get interval {
    if (type == TaskRepeatType.days && unit == RepeatUnit.week) {
      return period ~/ 7;
    }
    return period < 1 ? 1 : period;
  }

  /// 由「每 N 单位」构造出模型层需要的 type + period。
  static RepeatSetting fromUnit({
    required RepeatUnit unit,
    required int interval,
    required bool endless,
    DateTime? endsDate,
  }) {
    final n = interval < 1 ? 1 : interval;
    switch (unit) {
      case RepeatUnit.day:
        return RepeatSetting(
            type: TaskRepeatType.days,
            period: n,
            endless: endless,
            endsDate: endsDate);
      case RepeatUnit.week:
        return RepeatSetting(
            type: TaskRepeatType.days,
            period: n * 7,
            endless: endless,
            endsDate: endsDate);
      case RepeatUnit.month:
        return RepeatSetting(
            type: TaskRepeatType.month,
            period: n,
            endless: endless,
            endsDate: endsDate);
      case RepeatUnit.year:
        return RepeatSetting(
            type: TaskRepeatType.year,
            period: n,
            endless: endless,
            endsDate: endsDate);
    }
  }

  String get label {
    switch (type) {
      case TaskRepeatType.norepeat:
        return '不重复';
      case TaskRepeatType.weekday:
        return '每周工作日';
      case TaskRepeatType.days:
        if (period <= 1) return '每天重复';
        if (unit == RepeatUnit.week) {
          return interval <= 1 ? '每周重复' : '每 $interval 周重复';
        }
        return '每 $period 天重复';
      case TaskRepeatType.month:
        return period <= 1 ? '每月重复' : '每 $period 月重复';
      case TaskRepeatType.year:
        return period <= 1 ? '每年重复' : '每 $period 年重复';
    }
  }
}

/// 钉钉风格的重复规则选择弹窗。返回 null 表示用户取消。
Future<RepeatSetting?> showRepeatSheet(
  BuildContext context,
  RepeatSetting initial,
) {
  return showCupertinoModalPopup<RepeatSetting>(
    context: context,
    builder: (BuildContext context) => _RepeatSheet(initial: initial),
  );
}

class _RepeatSheet extends StatelessWidget {
  final RepeatSetting initial;

  const _RepeatSheet({required this.initial});

  bool _isSelected(RepeatSetting other) {
    if (initial.type != other.type) return false;
    if (other.type == TaskRepeatType.norepeat ||
        other.type == TaskRepeatType.weekday) {
      return true;
    }
    return initial.period == other.period;
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool chevron = false,
  }) {
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 20,
              color: selected
                  ? CupertinoColors.systemBlue
                  : CupertinoDynamicColor.resolve(
                      CupertinoColors.tertiaryLabel, context),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 16, color: textColor),
              ),
            ),
            if (chevron)
              Icon(
                CupertinoIcons.chevron_right,
                size: 15,
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.tertiaryLabel, context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(
        height: 0.5,
        margin: const EdgeInsets.only(left: 58),
        color:
            CupertinoDynamicColor.resolve(CupertinoColors.separator, context),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemBackground, context),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _row(
              context,
              label: '不重复',
              selected:
                  _isSelected(RepeatSetting(type: TaskRepeatType.norepeat)),
              onTap: () => Navigator.of(context)
                  .pop(RepeatSetting(type: TaskRepeatType.norepeat)),
            ),
            _divider(context),
            _row(
              context,
              label: '每天重复',
              selected: _isSelected(RepeatSetting(type: TaskRepeatType.days)),
              onTap: () => Navigator.of(context)
                  .pop(RepeatSetting(type: TaskRepeatType.days, period: 1)),
            ),
            _divider(context),
            _row(
              context,
              label: '每周重复',
              selected: _isSelected(
                  RepeatSetting(type: TaskRepeatType.days, period: 7)),
              onTap: () => Navigator.of(context)
                  .pop(RepeatSetting(type: TaskRepeatType.days, period: 7)),
            ),
            _divider(context),
            _row(
              context,
              label: '每月重复',
              selected: _isSelected(RepeatSetting(type: TaskRepeatType.month)),
              onTap: () => Navigator.of(context)
                  .pop(RepeatSetting(type: TaskRepeatType.month, period: 1)),
            ),
            _divider(context),
            _row(
              context,
              label: '每年重复',
              selected: _isSelected(RepeatSetting(type: TaskRepeatType.year)),
              onTap: () => Navigator.of(context)
                  .pop(RepeatSetting(type: TaskRepeatType.year, period: 1)),
            ),
            _divider(context),
            _row(
              context,
              label: '每周工作日（跳过双休日）',
              selected:
                  _isSelected(RepeatSetting(type: TaskRepeatType.weekday)),
              onTap: () => Navigator.of(context)
                  .pop(RepeatSetting(type: TaskRepeatType.weekday)),
            ),
            _divider(context),
            _row(
              context,
              label: '自定义重复',
              selected: false,
              chevron: true,
              onTap: () async {
                final result = await showCupertinoModalPopup<RepeatSetting>(
                  context: context,
                  builder: (BuildContext context) =>
                      _CustomRepeatSheet(initial: initial),
                );
                if (result != null && context.mounted) {
                  Navigator.of(context).pop(result);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CustomRepeatSheet extends StatefulWidget {
  final RepeatSetting initial;

  const _CustomRepeatSheet({required this.initial});

  @override
  State<_CustomRepeatSheet> createState() => _CustomRepeatSheetState();
}

class _CustomRepeatSheetState extends State<_CustomRepeatSheet> {
  late RepeatUnit _unit;
  late int _interval;
  late bool _endless;
  late DateTime _endsDate;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial.type == TaskRepeatType.norepeat) {
      _unit = RepeatUnit.day;
      _interval = 2;
      _endless = true;
      _endsDate = DateTime.now();
    } else if (initial.type == TaskRepeatType.weekday) {
      _unit = RepeatUnit.day;
      _interval = 2;
      _endless = initial.endless;
      _endsDate = initial.endsDate;
    } else {
      _unit = initial.unit;
      _interval = initial.interval;
      _endless = initial.endless;
      _endsDate = initial.endsDate;
    }
  }

  RepeatSetting get _setting => RepeatSetting.fromUnit(
        unit: _unit,
        interval: _interval,
        endless: _endless,
        endsDate: _endsDate,
      );

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

  Widget _chip({
    required Widget child,
    VoidCallback? onTap,
  }) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemGroupedBackground, context),
        borderRadius: BorderRadius.circular(20),
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

  Future<void> _pickInterval() async {
    final maxValue =
        _unit == RepeatUnit.month || _unit == RepeatUnit.year ? 12 : 99;
    await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return CupertinoPageScaffold(
          child: SizedBox(
            height: MediaQuery.of(context).size.height / 3,
            child: CupertinoPicker(
              itemExtent: 32,
              scrollController:
                  FixedExtentScrollController(initialItem: _interval - 1),
              onSelectedItemChanged: (value) {
                setState(() => _interval = value + 1);
              },
              children: List.generate(
                maxValue,
                (index) => Center(child: Text('${index + 1}')),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickUnit() async {
    // ===== MOD: 换成全 App 统一的钉钉风格弹层（原来是 iOS 原生 ActionSheet）=====
    final picked = await showDingTalkSheet<RepeatUnit>(
      context: context,
      title: '重复单位',
      current: _unit,
      options: [
        for (final unit in RepeatUnit.values)
          DingTalkSheetOption(label: repeatUnitName[unit]!, value: unit),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _unit = picked;
      final maxValue =
          picked == RepeatUnit.month || picked == RepeatUnit.year ? 12 : 99;
      if (_interval > maxValue) _interval = maxValue;
    });
  }

  Future<void> _pickEndsDate() async {
    final result = await showDateTimeSheet(
      context,
      initial:
          _endsDate.isBefore(DateTime(2000, 1, 1)) ? DateTime.now() : _endsDate,
      title: '重复结束日期',
      withTime: false,
    );
    if (result != null && mounted) {
      setState(() => _endsDate = result);
    }
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
              child: Row(
                children: [
                  Text(
                    '重复周期：${_setting.label}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
            _card(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Text('每',
                          style: TextStyle(fontSize: 16, color: textColor)),
                      const SizedBox(width: 10),
                      _chip(
                        onTap: _pickInterval,
                        child: Text('$_interval',
                            style: TextStyle(fontSize: 15, color: textColor)),
                      ),
                      const SizedBox(width: 8),
                      _chip(
                        onTap: _pickUnit,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(repeatUnitName[_unit]!,
                                style:
                                    TextStyle(fontSize: 15, color: textColor)),
                            const SizedBox(width: 4),
                            Icon(CupertinoIcons.chevron_down,
                                size: 12, color: labelColor),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 12, bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('结束重复',
                    style: TextStyle(fontSize: 13, color: labelColor)),
              ),
            ),
            _card(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoSlidingSegmentedControl<bool>(
                          groupValue: _endless,
                          children: const {
                            true: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('无限重复'),
                            ),
                            false: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('终止于某一天'),
                            ),
                          },
                          onValueChanged: (value) {
                            if (value != null) {
                              setState(() => _endless = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_endless)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        _chip(
                          onTap: _pickEndsDate,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.calendar,
                                  size: 16, color: labelColor),
                              const SizedBox(width: 8),
                              Text(
                                _endsDate.isBefore(DateTime(2000, 1, 1))
                                    ? '请选择日期'
                                    : TimeHelper.chineseDate(_endsDate),
                                style:
                                    TextStyle(fontSize: 15, color: textColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
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
                      onPressed: () => Navigator.of(context).pop(_setting),
                      child: const Text('确定',
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
