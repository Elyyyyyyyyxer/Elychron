import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/focus_session.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/mod/focus_anchor.dart';
import 'package:celechron/utils/global.dart';
import 'package:get/get.dart';
import 'package:celechron/design/app_route.dart';
import 'package:celechron/mod/focus_suspend.dart';
import 'package:celechron/page/focus/focus_page.dart';
import 'package:flutter/cupertino.dart';

/// ===== P3：专注的两个入口 =====
///
/// ① 待办详情页的开始专注， 把这条待办和专注时长绑在一起；
/// ② 待办页右上角的计时器图标， 自由专注（敲代码、看书…），不挂任务。
///
/// 两个入口都进同一个 [FocusPage]，返回值表示这次专注是否正常结束。
Future<bool?> startFocusFor(
  BuildContext context, {
  Task? task,
  String? freeLabel,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    appPageRoute<bool>(
      builder: (BuildContext context) =>
          FocusPage(task: task, freeLabel: freeLabel),
    ),
  );
}

/// 继续一次暂停后离开的专注（见 `mod/focus_suspend.dart`）。
///
/// 用户 2026-09-16 的要求：暂停时能去别的页面办事，回来接着这一次专注做。
Future<bool?> resumeFocusFor(BuildContext context, SuspendedFocus suspended) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    appPageRoute<bool>(
      builder: (BuildContext context) => FocusPage(resume: suspended),
    ),
  );
}

/// 自由专注：先问一句这次专注叫什么，再开始。
///
/// 不填也能开始（就叫专注），不强迫用户先起名。
Future<bool?> startFreeFocus(BuildContext context) async {
  final controller = TextEditingController();
  final name = await showCupertinoDialog<String>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: const Text('自由专注'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('给这次专注起个名字（可以留空）：', style: TextStyle(fontSize: 13)),
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
          child: const Text('开始'),
          onPressed: () => Navigator.of(context).pop(controller.text),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || !context.mounted) return null;
  return startFocusFor(context, freeLabel: name);
}

/// ===== 2026-09-30：杀后台回来，静默接回"还在跑"的专注 =====
///
/// 用户原话：「杀后台之前处于什么状态（专注进行中，专注暂停，休息进行中，休息暂停）
/// 做好记录，回来后读取时间进行比较，确认现在应该处于什么状态后直接静默继续
/// （这也就意味着开屏会直接进入专注界面）」。
///
/// 和"暂停后离开"（[SuspendedFocus]，用户**主动**按的暂停）分得很清楚：
/// - 主动暂停 → 走首页那张继续卡片，回来看见的是暂停（用户选的 (a)：暂停不计时）；
/// - App 被系统杀掉时还在跑 → **用户没按过任何东西**，所以不问，把离开期间的时间
///   按"工作↔休息"逐段补上（见 [advanceFocusAnchor]），直接接着跑。
///
/// 返回 true 表示已经接管。
Future<bool> autoResumeInterruptedFocus() async {
  final db = _db;
  if (db == null) return false;
  // 专注页本来就开着（用户只是切出去又切回来）→ 别叠第二层
  if (FocusPage.isOpen) return false;
  final suspended = db.suspendedFocus();
  final anchor = FocusAnchorStore.load();
  // 日志：真机上靠 `adb logcat | findstr focus-resume` 就能看清它为什么(没)接管
  // ignore: avoid_print
  print('[focus-resume] anchor=' +
      (anchor == null ? 'none' : anchor.phase.name + '@' + anchor.phaseSince.toIso8601String()) +
      ' suspended=' +
      (suspended == null ? 'none' : suspended.uid + '@' + suspended.at.toIso8601String()));

  if (anchor == null) return false;
  // 暂停态不接管（用户选的 (a)：回来仍然是暂停，交给首页那张继续卡片）
  if (anchor.phase == FocusPhaseName.paused) {
    // ignore: avoid_print
    print('[focus-resume] 锚点是暂停 → 不接管');
    return false;
  }
  // ===== 2026-09-30 修正：老暂停不再挡住自动接回 =====
  //
  // 用户实测「杀后台回来没有自动进专注页」。原因是这里原来写成
  // "只要库里存在一条暂停记录就直接放弃" —— 而他库里恰好留着一条**很久以前**
  // 的暂停（他之前反馈过"很久以前的暂停还在"），于是自动接回永远进不去。
  // 现在只有"这条暂停就是当前这次会话"时才让位；别的老记录不挡路。
  if (suspended != null && suspended.uid == anchor.uid) {
    // ignore: avoid_print
    print('[focus-resume] 这条会话正是用户主动暂停的那条 → 留给卡片');
    return false;
  }

  final now = DateTime.now();
  final advanced = advanceFocusAnchor(anchor, now);

  // 会话记录：把推进后的累计时长写回去，否则"离开这一段"就白干了
  // （用户之前丢的就是这几个小时）
  FocusSession? session;
  for (final item in db.getUnfinishedFocusSessions()) {
    if (item.uid == anchor.uid) {
      session = item;
      break;
    }
  }
  if (session == null) {
    // ignore: avoid_print
    print('[focus-resume] 没找到未结算的会话记录 → 不接管，并清掉这个说谎的锚点');
    // 锚点说"在跑"、库里却已经没有未结算的会话（上次正常结束/被结算过）——
    // 留着它只会让下一轮判断继续迷惑，清掉。
    await FocusAnchorStore.clear();
    return false;
  }
  session
    ..focusedTime = advanced.worked(now)
    ..restTime = advanced.rested(now);
  await db.saveFocusSession(session);
  await FocusAnchorStore.save(advanced);

  // 交给专注页继续跑（它自己每秒 tick，进来就是"进行中"）
  final resume = SuspendedFocus(
    uid: anchor.uid,
    remaining: advanced.currentSegmentRemaining(now),
    wasResting: advanced.phase == FocusPhaseName.resting,
    at: now,
  );
  db.saveSuspendedFocus(resume);

  // ignore: avoid_print
  print('[focus-resume] 接管：' + advanced.phase.name + '，剩余 ' + advanced.currentSegmentRemaining(now).inSeconds.toString() + ' 秒');
  final context = navigatorKey.currentContext;
  if (context == null) return false; // 界面还没起来，锚点已更新，下次再接管
  await Navigator.of(context, rootNavigator: true).push<bool>(
    appPageRoute<bool>(
      // autoContinue：接回来直接跑，不停在"中断中"等用户点继续
      builder: (BuildContext context) =>
          FocusPage(resume: resume, autoContinue: true),
    ),
  );
  return true;
}

DatabaseHelper? get _db {
  try {
    return Get.find<DatabaseHelper>(tag: 'db');
  } catch (_) {
    return null;
  }
}
