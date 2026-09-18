import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/focus_engine.dart';
import 'package:celechron/model/focus_stats.dart';
import 'package:celechron/mod/focus_runtime.dart';
import 'package:celechron/mod/focus_suspend.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/focus/focus_entry.dart';
import 'package:celechron/page/focus/focus_stats_page.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// 上一次专注还没结束时，用户选了什么（见 [FocusHomePage] 的开始守卫）
enum _PendingFocusChoice { resume, finishAndStart }

/// ===== 专注标签页：一个坐下就能按的入口 =====
///
/// 中间那个大圆就是唯一的主操作：按它就开始专注。
/// 上面选定专注对象，要么挑一条待办，要么给这次专注起个名字；
/// 什么都不选也能直接开始（就叫专注）。
/// 下面那条进专注记录。
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

  /// 进来时"接住"了一条被系统中断的专注，就给用户一句说明
  String? _adoptedNotice;

  @override
  void initState() {
    super.initState();
    // ===== 接住被系统中断的专注（2026-09-17 用户反馈）=====
    //
    // 用户原话：「外面通过分享进入 Elychron 会打断专注」。
    // 真相：App 被系统杀掉后，未结算的会话一直躺在库里，下次进专注页就被
    // 当成僵尸结算成异常结束。这里先把它转成"可以继续"，用户就不会白干。
    final db = _db;
    if (db != null) {
      final adopted = adoptStaleFocusSessions(db);
      if (adopted != null) {
        _adoptedNotice = '上次专注（${focusHuman(adopted.focusedTime)}）中途被系统打断了，'
            '已经保留在这里，可以继续';
      }
    }
    _syncFocusRuntime();
  }

  /// 把"有没有一次专注停着等继续"同步给全局（分享拦截与开始守卫都读它）
  void _syncFocusRuntime() {
    FocusRuntime.set(
        _suspended != null ? FocusRunState.paused : FocusRunState.idle);
  }

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

  /// 有一次"暂停后离开"的专注还留着吗（见 mod/focus_suspend.dart）
  SuspendedFocus? get _suspended => _db?.suspendedFocus();

  /// 那张卡上的一句话：叫什么 · 已经专注多久 · 什么时候走开的
  String get _suspendedHint {
    final suspended = _suspended;
    if (suspended == null) return '';
    final session = _db?.suspendedSession();
    final name = session?.displayName ?? '专注';
    final focused = session?.focusedTime ?? Duration.zero;
    final minutes = DateTime.now().difference(suspended.at).inMinutes;
    final ago = minutes <= 0
        ? '刚刚'
        : (minutes < 60 ? '$minutes 分钟前' : '${minutes ~/ 60} 小时前');
    return '$name· 已专注 ${focusHuman(focused)} · $ago暂停';
  }

  /// 继续那次暂停中的专注
  Future<void> _resumeSuspended() async {
    final suspended = _suspended;
    if (suspended == null) return;
    await resumeFocusFor(context, suspended);
    // 回来之后重新判定：接着做（running）、又停在那儿（paused）、或已结算（idle）
    if (mounted) {
      setState(() {});
      _syncFocusRuntime();
    }
  }

  /// 不想继续了：把那次暂停中的专注结算掉
  Future<void> _finishSuspended() async {
    final db = _db;
    final suspended = _suspended;
    final session = db?.suspendedSession();
    if (db == null || suspended == null || session == null) {
      db?.clearSuspendedFocus();
      if (mounted) setState(() {});
      return;
    }
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('结束这次专注？'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '已经专注 ${focusHuman(session.focusedTime)}'
            '${session.taskUid != null ? '，结束后会计入这条待办' : '，结束后只进专注记录'}。',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('结束'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    settleFocusSession(db, session, completed: true);
    db.clearSuspendedFocus();
    setState(() {});
    _syncFocusRuntime();
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

  /// 从待我处理里挑一条
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
            child: Text('待我处理里现在是空的。先去待办页建一条，或者直接开始自由专注。',
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
                                if (already)
                                  '已专注 ${focusHuman(task.timeSpent)}',
                              ].where((e) => e.isNotEmpty).join(' · '),
                              style: TextStyle(fontSize: 12, color: labelColor),
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
              const Text('比如敲代码看书写报告：', style: TextStyle(fontSize: 13)),
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
    // ===== 已经有一次专注停在那儿时，先问清楚（2026-09-17 用户反馈）=====
    //
    // 用户原话：「存在暂停的专注时直接点击开始专注，会强制打断上一次的专注
    // 并记为未正常」。以前这里是无脑开新的一次，旧的那条就成了"未正常结束"。
    // 现在给三个选择：继续上一次 / 结束并开始新的 / 取消。
    if (_suspended != null) {
      final choice = await _askAboutPendingFocus();
      if (choice == null || !mounted) return;
      if (choice == _PendingFocusChoice.resume) {
        await _resumeSuspended();
        return;
      }
      // 结束并开始新的：把上一次**正常结算**（用户认了这段时间）
      await _finishSuspended();
      if (!mounted) return;
    }

    final task = _task;
    await startFocusFor(
      context,
      task: task,
      freeLabel: task == null ? _freeLabel : null,
    );
    if (mounted) {
      setState(() {}); // 回来刷新今天已专注
      _syncFocusRuntime();
    }
  }

  /// 上一次专注还没结束：继续它，还是结束它再开新的？
  Future<_PendingFocusChoice?> _askAboutPendingFocus() async {
    final session = _db?.suspendedSession();
    final focused = session?.focusedTime ?? Duration.zero;
    final name = session?.displayName ?? '专注';
    return showCupertinoDialog<_PendingFocusChoice>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('上一次专注还没结束'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '$name，已经专注 ${focusHuman(focused)}。\n'
            '直接开始新的会把这一次结束掉，先选一个：',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('继续上一次'),
            onPressed: () =>
                Navigator.of(context).pop(_PendingFocusChoice.resume),
          ),
          CupertinoDialogAction(
            child: const Text('结束并开始新的'),
            onPressed: () =>
                Navigator.of(context).pop(_PendingFocusChoice.finishAndStart),
          ),
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
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
      backgroundColor: pageBackground(context),
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

            // ===== MOD: 有一次专注还没结束的继续入口（2026-09-16）=====
            // 暂停时离开专注页**不会结束**这次专注（见 mod/focus_suspend.dart），
            // 所以这里要把它显式摆出来，否则用户找不到回去的路。
            if (_suspended != null) ...[
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _card(
                  children: [
                    Row(
                      children: [
                        Icon(CupertinoIcons.pause_circle_fill,
                            size: 22, color: AppAccent.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '有一次专注还没结束',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(_suspendedHint,
                        style: TextStyle(fontSize: 12, color: labelColor)),
                    // 这条是"被系统打断、我们替你接住"的，多说一句免得用户以为是脏数据
                    if (_adoptedNotice != null) ...[
                      const SizedBox(height: 6),
                      Text(_adoptedNotice!,
                          style: TextStyle(fontSize: 12, color: labelColor)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _actionChip(
                            context,
                            icon: CupertinoIcons.play_fill,
                            label: '继续',
                            onTap: _resumeSuspended,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionChip(
                            context,
                            icon: CupertinoIcons.checkmark_alt,
                            label: '结束并结算',
                            onTap: _finishSuspended,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ],

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
                      builder: (BuildContext context) => const FocusStatsPage(),
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
                '时长可在设置 → 专注时长里改（现在是 '
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
