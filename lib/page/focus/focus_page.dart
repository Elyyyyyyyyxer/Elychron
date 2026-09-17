import 'package:celechron/design/app_accent.dart';
import 'package:celechron/mod/do_not_disturb.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/course_mount_store.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/mod/focus_suspend.dart';
import 'package:celechron/model/focus_engine.dart';
import 'package:celechron/model/focus_session.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/task.dart';
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

  /// 带着一次「暂停后离开」的专注进来（null = 全新开始）。
  ///
  /// 见 `lib/mod/focus_suspend.dart`：暂停时离开**不结束这次专注**，
  /// 专注首页会给出「继续」入口，点它就把它传进来，原样接着做。
  final SuspendedFocus? resume;

  const FocusPage({super.key, this.task, this.freeLabel, this.resume});

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  late final FocusEngine _engine;
  late final FocusSession _session;
  Timer? _ticker;
  int _ticks = 0;
  FocusPhase _lastPhase = FocusPhase.idle;

  /// 上一次实际应用的免打扰状态（true = 静音中）。
  ///
  /// 只用来判断"要不要动系统设置"，见 [_onTick] 里的对齐检查。
  bool? _lastSilenced;

  /// 打开页面时结算的「上次没正常结束」的会话（用于提示一句）
  String? _recoveredNotice;

  /// true = 这次是「暂停后离开，回来接着做」（见 [FocusPage.resume]）
  bool _resumedExisting = false;

  /// 「专注自动计入课程」这个开关这次是开着的吗（关掉时页面上要说明）
  bool _attributeEnabled = true;

  /// 这次专注算到了哪门课上（课程名；null = 没有归属）。
  ///
  /// ★ 为什么要在页面上显示（用户 2026-09-17）：
  /// 归属是"拿开始时间在课表里找那一节课"，命中与否取决于**当时有没有课**。
  /// 原来页面上一声不吭，用户只能事后去统计页翻「按月按课程」猜 ——
  /// 于是就有了"当现在有课的时候，自由专注不会自动计入当前课程？"这个疑问。
  /// 现在开始专注时就把结果显示出来：一眼就能看出这次算到了哪门课。
  String? _attributedCourseName;

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
    if (free.isNotEmpty) return free;
    // 「回来接着做」时不会再传 task / freeLabel，就用会话里记着的那个名字
    // （否则休息提醒会变成干巴巴一句"该休息了"，看不出是哪次专注）
    if (_resumedExisting) {
      final name = _session.displayName;
      if (name.isNotEmpty) return name;
    }
    return '专注';
  }

  @override
  void initState() {
    super.initState();
    // 上次被系统杀掉留下的会话按最后记录结算（"暂停后离开"的那条会跳过，见方法内注释）
    _settleStaleSessions();
    _engine = FocusEngine(
      workMinutes: _workMinutes,
      restMinutes: _restMinutes,
    );

    // ===== 是不是"回来接着做" =====
    final resumedSession =
        widget.resume == null ? null : _db?.suspendedSession();
    if (resumedSession != null) {
      // 原样接回来：**不新建会话、不重置计时**，停在上次按暂停的地方
      _session = resumedSession;
      _resumedExisting = true;
      _engine.restore(
        now: DateTime.now(),
        focused: resumedSession.focusedTime,
        rested: resumedSession.restTime,
        rounds: resumedSession.rounds,
        remaining: widget.resume!.remaining,
        wasResting: widget.resume!.wasResting,
      );
    } else {
      _engine.start(DateTime.now());
      final startedAt = DateTime.now();
      _session = FocusSession(
        taskUid: widget.task?.uid,
        label: _label,
        startedAt: startedAt,
        workMinutes: _workMinutes,
        restMinutes: _restMinutes,
        courseId: _courseIdFor(startedAt),
      );
      _db?.saveFocusSession(_session);
    }
    _attributeEnabled = _db?.getFocusAttributeToCourse() ?? true;
    final attributedId = _session.courseId;
    _attributedCourseName = (attributedId == null || attributedId.isEmpty)
        ? null
        : courseNameOf(attributedId);

    _lastPhase = _engine.phase;
    // 一开始就把「该休息了」排进系统（锁屏也响）
    _syncRestNotice();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    // 页面关掉时把会话结算掉（正常结束走 _finish，这条路是兜底）
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
    // 专注期间自动免打扰（设置里可关；没授权时安静跳过，设置页会引导授权）
    if (DoNotDisturb.autoEnabled()) {
      DoNotDisturb.enableForFocus();
    }
  }

  /// 页面上那句归属说明（永远给出一个**明确**的答案，不留悬念）。
  String get _attributionLine {
    if (!_attributeEnabled) return '专注自动计入课程：已关闭（设置 → 专注里可打开）';
    // 判断依据是**会话里真的记了 courseId**，而不是"名字查得到" ——
    // 课表没刷出来时名字可能查不到，但归属本身是发生的。
    final id = _session.courseId;
    if (id != null && id.isNotEmpty) {
      return '本次专注会计入《${_attributedCourseName ?? "课表里的一门课"}》';
    }
    return '本次专注不归属课程（开始时课表里没有课）';
  }

  /// 这次专注算在哪门课上（课程挂载的第三件事，用户拍板"按开始时间判定 + 做成开关"）。
  ///
  /// - 开关关掉 → 一律不归属；
  /// - 待办自带课程归属 → 直接继承（用户建待办时明确选过，比按时间猜准）；
  /// - 否则拿**开始时间**去课表里找那一节，命中才算（口径见 [courseIdForFocusStart]）。
  ///
  /// 课表拿不到（没登录 / 还没抓到数据）就只保留"继承待办"这一条，
  /// **绝不因为归属失败而影响专注本身** —— 这是个锦上添花的功能。
  String? _courseIdFor(DateTime startedAt) {
    final explicit = widget.task?.courseId;
    try {
      if (!(_db?.getFocusAttributeToCourse() ?? true)) return null;
      if (explicit != null && explicit.isNotEmpty) return explicit;
      if (!Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) return null;
      final scholar = Get.find<Rx<Scholar>>(tag: 'scholar').value;
      return courseIdForFocusStart(
        startedAt: startedAt,
        // 直接传全量课时：每节的起止都是绝对时间，落在窗口里的自然只有当前那一节，
        // 不必再按"今天"筛一遍（也就不用依赖日历控制器是否已注册）。
        periodsOfDay: scholar.periods,
        explicitCourseId: null,
      );
    } catch (_) {
      return (explicit != null && explicit.isNotEmpty) ? explicit : null;
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
    // ★ 「暂停后离开」的那条**不算异常结束**：它是用户主动留着的，
    //   结算了就等于把"回来接着做"这件事毁掉。
    final suspendedUid = db.suspendedFocus()?.uid;
    final stale = db
        .getUnfinishedFocusSessions()
        .where((s) => s.uid != suspendedUid)
        .toList();
    if (stale.isEmpty) return;
    final minutes =
        stale.map((s) => s.focusedTime.inMinutes).fold<int>(0, (a, b) => a + b);
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
      // ===== MOD: 休息期间要把免打扰**关掉** =====
      //
      // 用户反馈：「切休息模式时不会自动关掉免打扰，导致无通知，我也不知道我要休息了」。
      // 原因：免打扰只在进/出专注页时开关（进=静音、走=还原），中间段切换没管它。
      // 语义上这也是对的：专注段静音，休息段要能收到消息 —— 否则休息提醒本身也可能被挡。
      _syncDoNotDisturbForPhase();
    }

    // ===== MOD: 免打扰再按「当前是不是工作段」对齐一次 =====
    //
    // 为什么不只靠上面那个「段变了」：暂停/继续、跳过休息这些按钮会**手动对齐**
    // `_lastPhase = _engine.phase`，那条路上的段切换收不到通知 —— 真机实测过：
    // 工作中点「暂停」，免打扰仍然是开的（本该还原成能收通知）。
    // 这里每秒只看一次「该不该静音」，任何路径换段都会在 1 秒内被纠正；
    // 而且只在状态**变化**时才真的动系统设置（enableForFocus/restore 本身也幂等）。
    if (_lastSilenced != _engine.isWorking) {
      _syncDoNotDisturbForPhase();
    }

    // 每 10 秒落一次库：App 被系统杀掉时最多损失 10 秒
    if (_ticks % 10 == 0) _flush();

    setState(() {});
  }

  /// 按当前阶段开关免打扰：**工作段静音、休息段还原**。
  ///
  /// 离开专注页时 `dispose` 还会再还原一次（幂等：没记录就什么都不做）。
  void _syncDoNotDisturbForPhase() {
    _lastSilenced = _engine.isWorking;
    if (!DoNotDisturb.autoEnabled()) return;
    if (_engine.isWorking) {
      DoNotDisturb.enableForFocus();
    } else {
      DoNotDisturb.restore();
    }
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

  /// 结算一次会话（实现挪到 `mod/focus_suspend.dart`，专注首页也要用同一份）
  void _settle(FocusSession session, {required bool completed}) =>
      settleFocusSession(_db, session, completed: completed);

  Future<void> _finish() async {
    _ticker?.cancel();
    _engine.stop();
    // 结束后不该再弹「该休息了」
    TaskReminder.cancelFocusRestNotice();
    _flush();
    _settle(_session, completed: true);
    // 既然结算了，"还有一次专注没结束"的入口就不能再留着
    _db?.clearSuspendedFocus();
    if (mounted) Navigator.of(context).pop(true);
  }

  /// 暂停着离开：**不结算**这次专注，把它留成"可以继续"，然后关掉页面。
  ///
  /// 用户的诉求见 `mod/focus_suspend.dart`：暂停时想去别的页面改条待办，
  /// 回来还能接着这次专注做。
  ///
  /// 为什么安全：暂停状态本来就不计时，离开多久都不影响时长；
  /// 会话记录在离开前再落一次库（`_flush`），引擎那两个存不进会话的值
  /// （这一段还剩多久 / 暂停前是工作还是休息）单独存一份。
  void _suspendAndLeave() {
    _ticker?.cancel();
    _flush();
    _db?.saveSuspendedFocus(SuspendedFocus(
      uid: _session.uid,
      remaining: _engine.remaining,
      wasResting: _engine.pausedFromResting,
      at: DateTime.now(),
    ));
    // 离开页面就不该再弹「该休息了」（回来继续时会重新排）
    TaskReminder.cancelFocusRestNotice();
    DoNotDisturb.restore();
    if (mounted) Navigator.of(context).pop(false);
  }

  /// 暂停并离开：先按暂停（如果还在跑），再走上面那条路
  void _pauseAndLeave() {
    if (!_engine.isPaused) _engine.pause();
    setState(() {});
    _suspendAndLeave();
  }

  Future<_ExitChoice> _confirmExit() async {
    // 一秒都没专注、也没休息过，就别问了 —— 直接按"结束"处理
    if (_engine.focused < const Duration(seconds: 30))
      return _ExitChoice.finish;
    final result = await showCupertinoDialog<_ExitChoice>(
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
          // ===== MOD: 多一个"暂停并离开"（2026-09-16 用户要求）=====
          // 以前只有"继续/结束"，想去改一条待办就只能把这次专注结束掉。
          CupertinoDialogAction(
            child: const Text('暂停并离开'),
            onPressed: () => Navigator.of(context).pop(_ExitChoice.suspend),
          ),
          CupertinoDialogAction(
            child: const Text('继续专注'),
            onPressed: () => Navigator.of(context).pop(_ExitChoice.stay),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('结束'),
            onPressed: () => Navigator.of(context).pop(_ExitChoice.finish),
          ),
        ],
      ),
    );
    return result ?? _ExitChoice.stay;
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
    final roundText =
        _engine.rounds == 0 ? '第 1 轮' : '第 ${_engine.rounds + 1} 轮';

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
            Text(_attributionLine,
                style: TextStyle(fontSize: 12, color: labelColor)),
            const SizedBox(height: 4),
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
            // ===== MOD: 暂停时明确告诉用户"可以走开"（2026-09-16 用户要求）=====
            // 不写这一句的话，"返回=结束专注"的旧印象还在，用户根本不敢按返回键。
            if (_engine.isPaused)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  '已暂停，不计时。现在可以直接返回：去改待办、回消息都行，'
                  '这次专注不会结束，回来在「专注」页点「继续」接着做。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: labelColor),
                ),
              ),
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
                        // ===== MOD: 按钮换段也要同步免打扰 =====
                        //
                        // 上面那行 `_lastPhase = _engine.phase` 是**手动对齐**，
                        // 于是 `_onTick` 里的「段变了」判断不会成立 —— 免打扰同步
                        // 就被跳过了（真机实测：工作中点暂停，免打扰仍然是开的）。
                        // 语义同休息段：不在工作段就该能收到通知。
                        _syncDoNotDisturbForPhase();
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
                              // ===== MOD: 同上 —— 回到工作段要重新静音 =====
                              _syncDoNotDisturbForPhase();
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
        // ===== MOD: 暂停状态下直接放行（2026-09-16 用户要求）=====
        // 「专注模式暂停状态下应当可以切换到其他页面，方便修改待办之类的」
        // —— 既然已经暂停了，返回键就不该再劝用户结束这次专注。
        if (_engine.isPaused) {
          _suspendAndLeave();
          return;
        }
        final choice = await _confirmExit();
        if (!mounted) return;
        switch (choice) {
          case _ExitChoice.finish:
            await _finish();
          case _ExitChoice.suspend:
            // 先按暂停再离开：这样"暂停前是工作还是休息"被引擎记下来，
            // 回来时才接得回原来那一段（休息中直接离开会记错）
            _pauseAndLeave();
          case _ExitChoice.stay:
            break;
        }
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

/// 从专注页离开时的三种选择（见 _FocusPageState._confirmExit）
enum _ExitChoice {
  /// 暂停并离开：**不结束**这次专注，去别的页面办完事回来接着做
  suspend,

  /// 继续专注（留在本页）
  stay,

  /// 结束这次专注并结算
  finish,
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
