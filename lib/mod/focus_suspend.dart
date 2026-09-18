import 'package:get/get.dart';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/focus_session.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_controller.dart';

/// ===== 暂停后离开，回来接着专注（2026-09-16）=====
///
/// 用户原话：专注模式暂停状态下应当可以切换到其他页面，方便修改待办之类的。
///
/// 以前从专注页返回就等于**结束这次专注**（要么弹结束这次专注？确认，要么直接结算），
/// 想中途去改一条待办，只能先把这次专注结束掉。
///
/// 现在：**暂停时**可以直接离开， 这次专注**不结算**，而是留档成"可以继续"；
/// 专注首页会出现一张继续进行中的专注卡片，点一下原样接着做。
///
/// 为什么暂停着离开是安全的：
/// - 暂停状态下**本来就不计时**（`FocusEngine` 只在 working / resting 时累加时间），
///   所以离开多久都不影响这次专注的时长；
/// - 会话记录本来就每 10 秒落一次库（`_flush`），离开时再落一次即可；
/// - 这一段还剩多久和暂停前是工作还是休息是引擎的内部状态、会话里没存，
///   所以单独补一份。
///
/// ⚠️ 这一份存 **optionsBox**（键值小盒子），**刻意不动 Hive 表结构**，
/// 给 FocusSession 加字段就必须同步改 adapter 的字段计数字节，2026-09-16 那次
/// App 打不开 + 待办全没正是漏改那个字节造成的（见 docs/WHATS_NEW_1.4.1.md 第十二节）。
/// 这种一次性的界面状态，不值得冒那个险。
const String _kSuspendedFocus = 'suspendedFocus';

/// 一次"暂停后离开"的专注。
///
/// 会话本身在 focusBox 里（`FocusSession`，`endedAt == null`），
/// 这里只补引擎内部那两个存不下的值。
class SuspendedFocus {
  /// 对应 [FocusSession.uid]
  final String uid;

  /// 暂停时**当前这一段**还剩多久（回来接着这里倒数）
  final Duration remaining;

  /// 暂停前是休息段吗（false = 工作段）
  final bool wasResting;

  /// 什么时候离开的（首页显示"暂停于 X 分钟前"）
  final DateTime at;

  const SuspendedFocus({
    required this.uid,
    required this.remaining,
    required this.wasResting,
    required this.at,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'remainingSeconds': remaining.inSeconds,
        'wasResting': wasResting,
        'at': at.millisecondsSinceEpoch,
      };

  /// 从 optionsBox 读出来的东西**什么都可能是**（旧版本、脏数据、手滑），
  /// 所以这里逐字段判类型，认不出来就当"没有暂停中的专注"，绝不抛。
  static SuspendedFocus? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['uid'];
    if (uid is! String || uid.isEmpty) return null;
    final seconds = raw['remainingSeconds'];
    final at = raw['at'];
    final safeSeconds = seconds is int && seconds > 0 ? seconds : 0;
    final safeAt = at is int && at > 0
        ? DateTime.fromMillisecondsSinceEpoch(at)
        : DateTime.now();
    return SuspendedFocus(
      uid: uid,
      remaining: Duration(seconds: safeSeconds),
      wasResting: raw['wasResting'] == true,
      at: safeAt,
    );
  }
}

extension FocusSuspendStore on DatabaseHelper {
  void saveSuspendedFocus(SuspendedFocus value) {
    optionsBox.put(_kSuspendedFocus, value.toMap());
  }

  SuspendedFocus? suspendedFocus() =>
      SuspendedFocus.fromMap(optionsBox.get(_kSuspendedFocus));

  void clearSuspendedFocus() {
    optionsBox.delete(_kSuspendedFocus);
  }

  /// 暂停中那次专注对应的会话记录（会话被删过就返回 null）
  FocusSession? suspendedSession() {
    final suspended = suspendedFocus();
    if (suspended == null) return null;
    for (final session in getFocusSessions()) {
      if (session.uid == suspended.uid) return session;
    }
    return null;
  }
}

/// ===== 把"App 被系统杀掉时留下的会话"接成可以继续的一次专注 =====
///
/// 用户反馈（2026-09-17）：「外面通过分享进入 Elychron 会把专注打断」，
/// 再进专注页还提示"上次没有正常结束"。
///
/// 真相：App 被杀之后，那条未结算的会话**一直躺在库里**，
/// 下次打开专注页就被 [FocusPage] 当"僵尸"结算成**异常结束**了。
/// 于是用户眼里就是"分享一下，专注没了"。
///
/// 现在：把**最新**那条转成"暂停中" —— 专注首页出现继续卡片，点一下就原样接着做，
/// 既不结算、也不记异常。更老的僵尸会话（正常使用下不会出现）仍按最后记录结算。
///
/// 返回被接住的那条会话（没有可接的就返回 null）。
FocusSession? adoptStaleFocusSessions(DatabaseHelper db) {
  // 已经有一条在等着继续了，就别再塞第二条
  if (db.suspendedFocus() != null) return null;
  final stale = db.getUnfinishedFocusSessions();
  if (stale.isEmpty) return null;

  stale.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final newest = stale.first;

  // 会话里只存了累计时长，没存引擎的内部状态（这一段还剩多久、是不是休息段），
  // 所以按"工作段长度减去已专注对工作段取余"推一个近似值。
  // 误差最多一个落库周期（10 秒），而且**离开期间本来就不该计时**，够用。
  final phaseSeconds = newest.workMinutes * 60;
  var remaining = Duration(
    seconds: phaseSeconds <= 0
        ? 60
        : phaseSeconds - (newest.focusedTime.inSeconds % phaseSeconds),
  );
  if (remaining < const Duration(minutes: 1)) {
    remaining = const Duration(minutes: 1);
  }
  db.saveSuspendedFocus(SuspendedFocus(
    uid: newest.uid,
    remaining: remaining,
    wasResting: false,
    at: newest.startedAt,
  ));

  for (final other in stale.skip(1)) {
    settleFocusSession(db, other, completed: false);
  }
  return newest;
}

/// 专注不到这么多秒的**不留记录**， 误触、进去看一眼就退出，
/// 不该污染统计，也不该往 timeSpent 里塞几秒。
const int minimalFocusSessionSeconds = 10;

/// 结算一次专注会话：写终态 + 把专注时长累加到对应待办的 `timeSpent`。
///
/// 原来这段是 `_FocusPageState._settle` 的私有方法；现在专注首页也要能
/// 结束并结算一次暂停中的会话，所以挪出来共用。**逻辑一字未改**。
void settleFocusSession(
  DatabaseHelper? db,
  FocusSession session, {
  required bool completed,
}) {
  if (session.focusedTime.inSeconds < minimalFocusSessionSeconds) {
    db?.deleteFocusSession(session.uid);
    return;
  }
  session
    ..endedAt = DateTime.now()
    ..completed = completed;
  db?.saveFocusSession(session);

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
