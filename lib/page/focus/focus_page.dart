import 'package:celechron/design/app_accent.dart';
import 'package:celechron/mod/do_not_disturb.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/focus_engine.dart';
import 'package:celechron/model/focus_session.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/utils/task_reminder.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ===== P3：专注页 =====
///
/// 一个页面就是一次专注会话：打开即开始，离开即结算。
/// 计时逻辑全在 [FocusEngine]（纯函数、可单测），这里只负责
/// 「每秒 tick 一次 + 画圆环 + 落库」。
class FocusPage extends StatefulWidget {
  /// 关联的待办（null = 自由专注）
  final Task? task;

  /// 自由专注的名字（如「敲代码」）
  final String? freeLabel;

  const FocusPage({super.key, this.task, this.freeLabel});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  late final FocusEngine _engine;
  late final FocusSession _session;
  Timer? _ticker;
  int _ticks = 0;
  FocusPhase _lastPhase = FocusPhase.idle;

  /// 打开页面时结算的「上次没正常结束」的会话（用于提示一句）
  String? _recoveredNotice;

  DatabaseHelper? get _db {
    if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return null;
    return Get.find<DatabaseHelper>(tag: 'db');
  }

  int get _workMinutes => _db?.getFocusWorkMinutes() ?? 60;
  int get _restMinutes => _db?.getFocusRestMinutes() ?? 15;
  bool get _restNotify => _db?.getFocusRestNotify() ?? true;

  String get _label {
    final task = widget.task;
    if (task != null && task.summary.trim().isNotEmpty) {
      return task.summary.trim();
    }
    final free = widget.freeLabel?.trim() ?? '';
    return free.isEmpty ? '专注' : free;
  }

  @override
  void initState() {
    super.initState();
    _settleStaleSessions();
    _engine = FocusEngine(
      workMinutes: _workMinutes,
      restMinutes: _restMinutes,
    );
    _engine.start(DateTime.now());
    _lastPhase = _engine.phase;
    // 一开始就把「该休息了」排进系统（锁屏也响）
    _syncRestNotice();

    _session = FocusSession(
      taskUid: widget.task?.uid,
      label: _label,
      startedAt: DateTime.now(),
      workMinutes: _workMinutes,
      restMinutes: _restMinutes,
    );
    _db?.saveFocusSession(_session);

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    // 页面关掉时把会话结算掉（正常结束走 _finish，这条路是兜底）
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
    // 专注期间自动免打扰（设置里可关；没授权时安静跳过，设置页会引导授权）
    if (DoNotDisturb.autoEnabled()) {
      DoNotDisturb.enableForFocus();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // 离开页面就把还没到点的「该休息了」撤掉，别让它半夜响
    TaskReminder.cancelFocusRestNotice();
    // 还原免打扰（只还原我们改过的；用户自己开着的话不动）
    DoNotDisturb.restore();
    super.dispose();
  }

  /// App 上次被系统杀掉时留下的「进行中」会话：按最后一次记录的进度如实结算，
  /// 并把专注时长补进对应待办，不让用户白干。
  void _settleStaleSessions() {
    final db = _db;
    if (db == null) return;
    final stale = db.getUnfinishedFocusSessions();
    if (stale.isEmpty) return;
    final minutes = stale
        .map((s) => s.focusedTime.inMinutes)
        .fold<int>(0, (a, b) => a + b);
    for (final session in stale) {
      _settle(session, completed: false);
    }
    _recoveredNotice = '上次专注（$minutes 分钟）没有正常结束，已按最后记录结算';
  }

  void _onTick() {
    if (!mounted) return;
    final now = DateTime.now();
    _engine.tick(now);
    _ticks++;

    // 段切换（工作→休息 / 休息→工作）时同步「该休息了」的系统排程
    if (_engine.phase != _lastPhase) {
      _lastPhase = _engine.phase;
      _syncRestNotice();
    }

    // 每 10 秒落一次库：App 被系统杀掉时最多损失 10 秒
    if (_ticks % 10 == 0) _flush();

    setState(() {});
  }

  /// 把「该休息了」按当前状态同步到**系统通知排程**。
  ///
  /// 只在「进入工作段」时排一条，时间 = 现在 + 这一段还剩多久；
  /// 不在工作段（休息中 / 暂停 / 已结束）就撤销它。
  ///
  /// 只在段切换或用户操作时调用 —— 每秒都调会把通知反复取消重排。
  void _syncRestNotice() {
    if (!_restNotify || !_engine.isWorking) {
      TaskReminder.cancelFocusRestNotice();
      return;
    }
    TaskReminder.scheduleFocusRestNotice(
      at: DateTime.now().add(_engine.remaining),
      label: _label,
    );
  }

  void _flush() {
    _session
      ..focusedTime = _engine.focused
      ..restTime = _engine.rested
      ..rounds = _engine.rounds;
    _db?.saveFocusSession(_session);
  }

  /// 结算一次会话：写终态 + 把专注时长累加到待办的 timeSpent
  ///
  /// 专注不到 [minimalSessionSeconds] 的**不留记录** —— 误触、进去看一眼就退出，
  /// 不该污染统计，也不该往 timeSpent 里塞几秒。
  static const int minimalSessionSeconds = 10;

  void _settle(FocusSession session, {required bool completed}) {
    if (session.focusedTime.inSeconds < minimalSessionSeconds) {
      _db?.deleteFocusSession(session.uid);
      return;
    }
    session
      ..endedAt = DateTime.now()
      ..completed = completed;
    _db?.saveFocusSession(session);

    final taskUid = session.taskUid;
    if (taskUid == null || session.focusedTime <= Duration.zero) return;
    try {
      final list = Get.find<RxList<Task>>(tag: 'taskList');
      for (final task in list) {
        if (task.uid != taskUid) continue;
        task.timeSpent = task.timeSpent + session.focusedTime;
        task.updatedAt = DateTime.now();
        break;
      }
      if (Get.isRegistered<TaskController>()) {
        final controller = Get.find<TaskController>();
        controller.updateDeadlineList();
        controller.taskList.refresh();
      }
    } catch (_) {
      // 任务列表还没准备好也不影响会话记录本身
    }
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    _engine.stop();
    // 结束后不该再弹「该休息了」
    TaskReminder.cancelFocusRestNotice();
    _flush();
    _settle(_session, completed: true);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<bool> _confirmExit() async {
    // 一秒都没专注、也没休息过，就别问了
    if (_engine.focused < const Duration(seconds: 30)) return true;
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('结束这次专注？'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '已经专注 ${focusHuman(_engine.focused)}'
            '${_engine.rounds > 0 ? '（${_engine.rounds} 轮）' : ''}'
            '，结束后会计入${widget.task != null ? '这条待办' : '专注记录'}。',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('继续专注'),
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
    return result ?? false;
  }

  // 时间显示统一走 focus_engine 里的 focusClock / focusHuman（那份有单测）


  // ------------------------------------------------------------------ UI

  Color get _phaseColor {
    if (_engine.isResting) return const Color(0xFF34C759); // 休息：绿
    if (_engine.isPaused) return const Color(0xFFFF9F0A); // 暂停：橙
    return AppAccent.primary; // 工作：主题粉
  }

  /// 当前这一段的总时长（工作段就是工作分钟数，休息段就是休息分钟数）
  Duration get _phaseTotal {
    if (_engine.isResting) return Duration(minutes: _restMinutes);
    return Duration(minutes: _workMinutes);
  }

  String get _phaseText {
    if (_engine.isPaused) {
      return _engine.remaining == Duration.zero ? '已暂停' : '已暂停';
    }
    if (_engine.isResting) return '休息中';
    return '工作中';
  }

  String get _phaseHint {
    if (_engine.isPaused) return '点「继续」接着计时';
    if (_engine.isResting) return '起来走走、喝口水';
    return '别碰手机，专心做完这一段';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final roundText = _engine.rounds == 0 ? '第 1 轮' : '第 ${_engine.rounds + 1} 轮';

    final page = CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('专注'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _finish,
          child: const Text('结束',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        border: null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_recoveredNotice != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _recoveredNotice!,
                  style: const TextStyle(
                      fontSize: 13, color: CupertinoColors.systemOrange),
                ),
              ),
            const Spacer(),
            // 大圆环
            SizedBox(
              width: 240,
              height: 240,
              child: CustomPaint(
                painter: _RingPainter(
                  progress: _engine.progress,
                  color: _phaseColor,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        // 按这一段的**总时长**决定格式：工作 60 分钟就整段显示 1:00:00 → 0:00:01，
                        // 不会中途从 1:00:00 突然变成 59:59
                        focusClock(_engine.remaining,
                            withHours: _phaseTotal >= const Duration(hours: 1)),
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w300,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _phaseText,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _phaseColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '$roundText · $_label',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
            ),
            const SizedBox(height: 6),
            Text(_phaseHint, style: TextStyle(fontSize: 13, color: labelColor)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stat(context, '已专注', focusHuman(_engine.focused)),
                const SizedBox(width: 28),
                _stat(context, '已休息', focusHuman(_engine.rested)),
                const SizedBox(width: 28),
                _stat(context, '完成', '${_engine.rounds} 轮'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '本轮参数：${_workMinutes} 分钟工作 / ${_restMinutes} 分钟休息'
              '（可在设置里改）',
              style: TextStyle(fontSize: 12, color: labelColor),
            ),
            const Spacer(),
            // 按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemFill, context),
                      borderRadius: BorderRadius.circular(24),
                      onPressed: () {
                        setState(() {
                          if (_engine.isPaused) {
                            _engine.resume(DateTime.now());
                          } else {
                            _engine.pause();
                          }
                        });
                        _lastPhase = _engine.phase;
                        _syncRestNotice(); // 暂停要撤掉排程，继续要重排
                      },
                      child: Text(_engine.isPaused ? '继续' : '暂停'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      color: _engine.isResting
                          ? CupertinoColors.systemGreen
                          : CupertinoColors.systemBlue,
                      borderRadius: BorderRadius.circular(24),
                      onPressed: _engine.isResting
                          ? () {
                              setState(() => _engine.skipRest());
                              _lastPhase = _engine.phase;
                              _syncRestNotice(); // 回到工作段：重排下一次休息提示
                            }
                          : () => setState(() {}),
                      child: Text(
                        _engine.isResting ? '跳过休息' : '再来一轮',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmExit()) await _finish();
      },
      child: page,
    );
  }

  Widget _stat(BuildContext context, String title, String value) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
        const SizedBox(height: 2),
        Text(title, style: TextStyle(fontSize: 12, color: labelColor)),
      ],
    );
  }
}

/// 大圆环：底色 + 进度弧
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.15);
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
