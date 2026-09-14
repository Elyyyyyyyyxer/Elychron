import 'package:celechron/design/app_accent.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/focus_engine.dart';
import 'package:celechron/model/focus_stats.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/focus/focus_entry.dart';
import 'package:celechron/page/focus/focus_stats_page.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ===== 专注标签页：一个「坐下就能按」的入口 =====
///
/// 中间那个大圆就是唯一的主操作：按它就开始专注。
/// 上面选定「专注对象」——要么挑一条待办，要么给这次专注起个名字；
/// 什么都不选也能直接开始（就叫「专注」）。
/// 下面那条进「专注记录」。
class FocusHomePage extends StatefulWidget {
  const FocusHomePage({super.key});

  @override
  State<FocusHomePage> createState() => _FocusHomePageState();
}

class _FocusHomePageState extends State<FocusHomePage> {
  /// 选中的待办（与 [_freeLabel] 二选一）
  Task? _task;

  /// 自由专注的名字
  String _freeLabel = '';

  DatabaseHelper? get _db {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return null;
    return Get.find<DatabaseHelper>(tag: 'db');
  }

  String get _targetLabel {
    final task = _task;
    if (task != null) {
      return task.summary.trim().isEmpty ? '(未命名待办)' : task.summary.trim();
    }
    return _freeLabel.trim().isEmpty ? '自由专注' : _freeLabel.trim();
  }

  /// 这次专注会记到哪里（给用户一句明白话）
  String get _targetHint {
    if (_task != null) return '结束后时长会记到这条待办上';
    return '不挂任务，只进专注记录';
  }

  Duration get _todayTotal {
    final sessions = _db?.getFocusSessions() ?? const [];
    final now = DateTime.now();
    return FocusStats.totalBetween(
      sessions,
      FocusStats.startOfToday(now),
      FocusStats.startOfToday(now).add(const Duration(days: 1)),
    );
  }

  Duration get _weekTotal {
    final sessions = _db?.getFocusSessions() ?? const [];
    final now = DateTime.now();
    return FocusStats.totalBetween(
      sessions,
      FocusStats.startOfWeek(now),
      FocusStats.startOfToday(now).add(const Duration(days: 1)),
    );
  }

  // ------------------------------------------------------------ 选专注对象

  /// 从「待我处理」里挑一条
  Future<void> _pickTask() async {
    List<Task> candidates = const [];
    try {
      candidates = Get.find<TaskController>().todoDeadlineList;
    } catch (_) {
      candidates = const [];
    }
    if (candidates.isEmpty) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (BuildContext context) => CupertinoAlertDialog(
          title: const Text('没有可选的待办'),
          content: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('「待我处理」里现在是空的。先去待办页建一条，或者直接开始自由专注。',
                style: TextStyle(fontSize: 14)),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('好'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
      return;
    }

    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;

    final picked = await showCupertinoModalPopup<Task>(
      context: context,
      builder: (BuildContext context) => Container(
        height: MediaQuery.of(context).size.height * 0.62,
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
                    const SizedBox(width: 72),
                    const Spacer(),
                    const Text('选一条待办',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(72, 44),
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
                  itemBuilder: (BuildContext context, int index) {
                    final task = candidates[index];
                    final already = task.timeSpent > Duration.zero;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(task),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.summary.trim().isEmpty
                                  ? '(未命名待办)'
                                  : task.summary.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, color: textColor),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                taskKindName[task.type] ?? '',
                                '截止 ${task.endTime.month}-${task.endTime.day} '
                                    '${task.endTime.hour.toString().padLeft(2, '0')}:'
                                    '${task.endTime.minute.toString().padLeft(2, '0')}',
                                if (already) '已专注 ${focusHuman(task.timeSpent)}',
                              ].where((e) => e.isNotEmpty).join(' · '),
                              style:
                                  TextStyle(fontSize: 12, color: labelColor),
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
    setState(() {
      _task = picked;
      _freeLabel = '';
    });
  }

  /// 给这次专注起个名字（自由专注）
  Future<void> _nameProject() async {
    final controller = TextEditingController(text: _freeLabel);
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('命名专注项目'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('比如「敲代码」「看书」「写报告」：',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: controller,
                placeholder: '敲代码 / 看书 / 写报告…',
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) => Navigator.of(context).pop(value),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('就用它'),
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    setState(() {
      _freeLabel = name.trim();
      _task = null;
    });
  }

  Future<void> _start() async {
    final task = _task;
    await startFocusFor(
      context,
      task: task,
      freeLabel: task == null ? _freeLabel : null,
    );
    if (mounted) setState(() {}); // 回来刷新「今天已专注」
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final today = _todayTotal;
    final week = _weekTotal;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('专注'),
        border: null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const SizedBox(height: 18),
            // 中间那个大圆：唯一的主操作
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _start,
                child: Container(
                  width: 208,
                  height: 208,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppAccent.primary, AppAccent.primaryLight],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppAccent.soft(0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(CupertinoIcons.timer,
                          size: 52, color: CupertinoColors.white),
                      SizedBox(height: 10),
                      Text(
                        '开始专注',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                today > Duration.zero
                    ? '今天已专注 ${focusHuman(today)}'
                    : '今天还没有专注记录',
                style: TextStyle(fontSize: 13, color: labelColor),
              ),
            ),

            // 专注对象
            const SizedBox(height: 26),
            _sectionTitle(context, '专注对象'),
            _card(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _targetLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textColor),
                        ),
                      ),
                      if (_task != null || _freeLabel.isNotEmpty)
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(32, 32),
                          onPressed: () => setState(() {
                            _task = null;
                            _freeLabel = '';
                          }),
                          child: Icon(CupertinoIcons.xmark_circle_fill,
                              size: 20, color: labelColor),
                        ),
                    ],
                  ),
                ),
                Text(_targetHint,
                    style: TextStyle(fontSize: 12, color: labelColor)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _actionChip(
                        context,
                        icon: CupertinoIcons.list_bullet,
                        label: '选择待办',
                        onTap: _pickTask,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _actionChip(
                        context,
                        icon: CupertinoIcons.pencil,
                        label: '命名项目',
                        onTap: _nameProject,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),

            // 专注记录
            const SizedBox(height: 8),
            _sectionTitle(context, '记录'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoListTile(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                backgroundColor: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemGroupedBackground, context),
                title: const Text('专注记录'),
                subtitle: Text(
                  '今天 ${focusHuman(today)} · 本周 ${focusHuman(week)}',
                  style: TextStyle(fontSize: 12, color: labelColor),
                ),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: CupertinoColors.tertiaryLabel),
                onTap: () async {
                  await Navigator.of(context, rootNavigator: true).push(
                    CupertinoPageRoute<void>(
                      builder: (BuildContext context) =>
                          const FocusStatsPage(),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '点中间的大圆开始。工作与休息会自动交替，'
                '时长可在「设置 → 专注时长」里改（现在是 '
                '${_db?.getFocusWorkMinutes() ?? 60} 分钟工作 / '
                '${_db?.getFocusRestMinutes() ?? 15} 分钟休息）。',
                style: TextStyle(fontSize: 12, color: labelColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(left: 28, top: 14, bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: CupertinoDynamicColor.resolve(
                CupertinoColors.secondaryLabel, context),
          ),
        ),
      );

  Widget _card({required List<Widget> children}) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

  Widget _actionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.tertiarySystemFill, context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppAccent.primary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
