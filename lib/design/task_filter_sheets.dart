import 'package:celechron/design/date_picker_sheet.dart';
import 'package:celechron/design/task_priority_color.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// 排序项：key + 名称
const Map<String, String> taskSortKeys = {
  'endTime': '截止时间',
  'createdAt': '创建时间',
  'updatedAt': '更新时间',
  'priority': '优先级',
};

String taskSortLabel(String key) => taskSortKeys[key] ?? '创建时间';

/// 截止时间筛选项
const Map<String, String> taskDueFilters = {
  'overdue': '已逾期',
  'today': '今天',
  'tomorrow': '明天',
  'week': '未来七天',
  'none': '未安排',
};

/// ===== P1：四种时间语义的筛选顺序 =====
///
/// 活动 / 截止 / 提醒 / 备忘 —— 就是界面上那一排的顺序，
/// `fixedlegacy`（内部《过去日程》）不出现，筛选时按「活动」归类。
const List<TaskType> taskKindFilterKinds = [
  TaskType.fixed,
  TaskType.deadline,
  TaskType.remind,
  TaskType.memo,
];

/// 点「类型」那一枚 chip 弹出来的小面板：只看某几种时间语义。
Future<void> showKindFilterSheet(
  BuildContext context,
  TaskController controller,
) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) => _KindFilterSheet(controller: controller),
  );
}

class _KindFilterSheet extends StatefulWidget {
  final TaskController controller;

  const _KindFilterSheet({required this.controller});

  @override
  State<_KindFilterSheet> createState() => _KindFilterSheetState();
}

class _KindFilterSheetState extends State<_KindFilterSheet> {
  late Set<TaskType> _kinds;

  @override
  void initState() {
    super.initState();
    _kinds = {...widget.controller.filterKinds};
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

    return _sheetShell(
      context,
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
          child: Row(
            children: [
              Text(
                '按时间类型筛选',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '不选任何一项就是全部类型',
              style: TextStyle(fontSize: 12, color: labelColor),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: taskKindFilterKinds.map((kind) {
              final active = _kinds.contains(kind);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  if (active) {
                    _kinds.remove(kind);
                  } else {
                    _kinds.add(kind);
                  }
                }),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: active
                        ? CupertinoDynamicColor.resolve(
                            CupertinoColors.tertiarySystemFill, context)
                        : CupertinoColors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              taskKindName[kind]!,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight:
                                    active ? FontWeight.w600 : FontWeight.w400,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              taskKindHint[kind]!,
                              style: TextStyle(fontSize: 12, color: labelColor),
                            ),
                          ],
                        ),
                      ),
                      if (active)
                        const Icon(CupertinoIcons.checkmark_alt,
                            size: 20, color: CupertinoColors.systemBlue),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
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
                  onPressed: () {
                    setState(() => _kinds.clear());
                    widget.controller.filterKinds.clear();
                  },
                  child: const Text('重置'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  color: CupertinoColors.systemBlue,
                  borderRadius: BorderRadius.circular(22),
                  onPressed: () {
                    widget.controller.filterKinds
                      ..clear()
                      ..addAll(_kinds);
                    Navigator.of(context).pop();
                  },
                  child: const Text('确定',
                      style: TextStyle(color: CupertinoColors.white)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _sheetShell(BuildContext context, {required List<Widget> children}) {
  return Container(
    decoration: BoxDecoration(
      color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemBackground, context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...children,
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ 排序

/// 图三：截止时间 / 创建时间 / 更新时间 / 优先级，各带升降序
Future<void> showSortSheet(
  BuildContext context,
  TaskController controller,
) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) => _SortSheet(controller: controller),
  );
}

class _SortSheet extends StatelessWidget {
  final TaskController controller;

  const _SortSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

    return _sheetShell(
      context,
      children: [
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // Obx 包裹，点哪一项高亮就移到哪一项、方向箭头同步变色
          child: Obx(
            () => Column(
              children: taskSortKeys.keys.map((key) {
                final active = controller.sortKey.value == key;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: active
                        ? CupertinoDynamicColor.resolve(
                            CupertinoColors.tertiarySystemFill, context)
                        : CupertinoColors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          taskSortKeys[key]!,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w400,
                            color: textColor,
                          ),
                        ),
                      ),
                      _dirButton(
                        context,
                        icon: CupertinoIcons.arrow_up,
                        active: active && controller.sortAscending.value,
                        onTap: () {
                          controller.sortKey.value = key;
                          controller.sortAscending.value = true;
                        },
                      ),
                      _dirButton(
                        context,
                        icon: CupertinoIcons.arrow_down,
                        active: active && !controller.sortAscending.value,
                        onTap: () {
                          controller.sortKey.value = key;
                          controller.sortAscending.value = false;
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _dirButton(
    BuildContext context, {
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onTap,
      child: Icon(
        icon,
        size: 20,
        color: active
            ? CupertinoColors.systemBlue
            : CupertinoDynamicColor.resolve(
                CupertinoColors.tertiaryLabel, context),
      ),
    );
  }
}

// ------------------------------------------------------------------ 筛选

/// 图四：完成状态 / 优先级 / 截止时间 / 创建人
Future<void> showFilterSheet(
  BuildContext context,
  TaskController controller,
) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) => _FilterSheet(controller: controller),
  );
}

class _FilterSheet extends StatefulWidget {
  final TaskController controller;

  const _FilterSheet({required this.controller});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late bool? _completed;
  late Set<TaskPriority> _priorities;
  late Set<TaskType> _kinds;
  late String? _due;
  late DateTime? _start;
  late DateTime? _end;

  @override
  void initState() {
    super.initState();
    _completed = widget.controller.filterCompleted.value;
    _priorities = {...widget.controller.filterPriorities};
    _kinds = {...widget.controller.filterKinds};
    _due = widget.controller.filterDue.value;
    _start = widget.controller.filterRangeStart.value;
    _end = widget.controller.filterRangeEnd.value;
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: CupertinoTheme.of(context).textTheme.textStyle.color,
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10, bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? (activeColor ?? CupertinoColors.systemBlue)
                  .withValues(alpha: 0.12)
              : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: active
                ? (activeColor ?? CupertinoColors.systemBlue)
                : CupertinoDynamicColor.resolve(
                    CupertinoColors.separator, context),
            width: active ? 1 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: active
                ? (activeColor ?? CupertinoColors.systemBlue)
                : CupertinoTheme.of(context).textTheme.textStyle.color,
          ),
        ),
      ),
    );
  }

  /// 日期用月历点选（平滑滑动），不用滚轮
  Future<void> _pickRange({required bool isStart}) async {
    final result = await showDateTimeSheet(
      context,
      initial: (isStart ? _start : _end) ?? DateTime.now(),
      title: isStart ? '开始日期' : '结束日期',
      withTime: false,
    );
    if (result == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = result;
      } else {
        _end = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Icon(CupertinoIcons.xmark_circle_fill,
                        size: 26, color: labelColor),
                  ),
                  const Spacer(),
                  const Text('筛选',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _sectionTitle(context, '完成状态'),
                  Wrap(
                    children: [
                      _chip(context,
                          label: '未完成',
                          active: _completed == false,
                          onTap: () => setState(() =>
                              _completed = _completed == false ? null : false)),
                      _chip(context,
                          label: '已完成',
                          active: _completed == true,
                          onTap: () => setState(() =>
                              _completed = _completed == true ? null : true)),
                    ],
                  ),
                  // ===== P1：按四种时间语义筛选 =====
                  _sectionTitle(context, '时间类型'),
                  Wrap(
                    children: taskKindFilterKinds.map((k) {
                      final active = _kinds.contains(k);
                      return _chip(
                        context,
                        label: taskKindName[k]!,
                        active: active,
                        onTap: () => setState(() {
                          if (active) {
                            _kinds.remove(k);
                          } else {
                            _kinds.add(k);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  _sectionTitle(context, '优先级'),
                  Wrap(
                    children: TaskPriority.values.reversed.map((p) {
                      final active = _priorities.contains(p);
                      return _chip(
                        context,
                        label: taskPriorityName[p]!,
                        active: active,
                        activeColor: taskPriorityColor(p),
                        onTap: () => setState(() {
                          if (active) {
                            _priorities.remove(p);
                          } else {
                            _priorities.add(p);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  _sectionTitle(context, '截止时间'),
                  Wrap(
                    children: taskDueFilters.entries.map((e) {
                      final active = _due == e.key;
                      return _chip(
                        context,
                        label: e.value,
                        active: active,
                        onTap: () =>
                            setState(() => _due = active ? null : e.key),
                      );
                    }).toList(),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pickRange(isStart: true),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.separator, context),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _start == null
                                  ? '开始日期'
                                  : TimeHelper.chineseDate(_start!),
                              style: TextStyle(fontSize: 15, color: labelColor),
                            ),
                          ),
                          Icon(CupertinoIcons.arrow_right,
                              size: 16, color: labelColor),
                          Expanded(
                            child: Text(
                              _end == null
                                  ? '结束日期'
                                  : TimeHelper.chineseDate(_end!),
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 15, color: labelColor),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(CupertinoIcons.calendar,
                              size: 18, color: labelColor),
                        ],
                      ),
                    ),
                  ),
                  _sectionTitle(context, '创建人'),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showCupertinoDialog(
                      context: context,
                      builder: (BuildContext context) => CupertinoAlertDialog(
                        title: const Text('本地版没有协作成员'),
                        content: const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('任务默认由你创建，暂不支持按创建人筛选。'),
                        ),
                        actions: [
                          CupertinoDialogAction(
                            child: const Text('知道了'),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.separator, context),
                          width: 0.5,
                        ),
                      ),
                      child: Text('选择创建人',
                          style: TextStyle(fontSize: 15, color: labelColor)),
                    ),
                  ),
                ],
              ),
            ),
            // 重置 / 确定
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
                      onPressed: () {
                        setState(() {
                          _completed = null;
                          _priorities = {};
                          _kinds = {};
                          _due = null;
                          _start = null;
                          _end = null;
                        });
                        widget.controller.resetFilters();
                      },
                      child: const Text('重置'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: CupertinoColors.systemBlue,
                      borderRadius: BorderRadius.circular(22),
                      onPressed: () {
                        widget.controller.filterCompleted.value = _completed;
                        widget.controller.filterPriorities
                          ..clear()
                          ..addAll(_priorities);
                        widget.controller.filterKinds
                          ..clear()
                          ..addAll(_kinds);
                        widget.controller.filterDue.value = _due;
                        widget.controller.filterRangeStart.value = _start;
                        widget.controller.filterRangeEnd.value = _end;
                        Navigator.of(context).pop();
                      },
                      child: const Text('确定',
                          style: TextStyle(color: CupertinoColors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
