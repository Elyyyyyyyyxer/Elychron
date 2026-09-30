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
  // 用户主动暂停的那一条：留着他自己决定
  if (db.suspendedFocus() != null) return false;

  final anchor = FocusAnchorStore.load();
  if (anchor == null) return false;
  if (anchor.phase == FocusPhaseName.paused) return false;

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
  if (session == null) return false;
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

  final context = navigatorKey.currentContext;
  if (context == null) return false; // 界面还没起来，锚点已更新，下次再接管
  await Navigator.of(context, rootNavigator: true).push<bool>(
    appPageRoute<bool>(
      builder: (BuildContext context) => FocusPage(resume: resume),
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
