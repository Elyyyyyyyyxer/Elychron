import 'dart:async';

import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_alarm_page.dart';
import 'package:celechron/page/task/task_create_page.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/utils/attachment_helper.dart';
import 'package:celechron/utils/share_receiver.dart';
import 'package:celechron/utils/task_alarm_center.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ============ 首页的魔改钩子：分享接收 + 闹钟弹出 ============
///
/// 上游的 `lib/page/home_page.dart` 在持续重构（1.3 就把标签机制整个换成了
/// PageView + _KeepAlivePage），所以魔改逻辑不塞在那个文件里，
/// 而是集中在这里；首页只保留 3 行挂载（见 `// ===== MOD =====` 标记）。
class HomeModHooks {
  HomeModHooks({required this.jumpToTaskTab});

  /// 切到「待办」标签页（首页那边是 _pageController.jumpToPage(2)）
  final void Function() jumpToTaskTab;

  StreamSubscription<List<SharedItem>>? _shareSubscription;
  bool _handlingShare = false;

  void start() {
    TaskAlarmCenter.current.addListener(_onAlarm);
    _listenShares();
  }

  void dispose() {
    TaskAlarmCenter.current.removeListener(_onAlarm);
    _shareSubscription?.cancel();
  }

  /// 闹钟到点：弹出全屏闹钟页
  void _onAlarm() {
    final task = TaskAlarmCenter.current.value;
    final context = Get.context;
    if (task == null || context == null) return;
    Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute(
        builder: (BuildContext context) => TaskAlarmPage(task: task),
        fullscreenDialog: true,
      ),
    );
  }

  /// 接收系统分享面板发来的图片/文件/文本 → 直接打开新建待办
  Future<void> _listenShares() async {
    try {
      final initial = await ShareReceiver.getInitial();
      if (initial.isNotEmpty) {
        await _handleShared(initial);
      }
      _shareSubscription = ShareReceiver.stream.listen((items) {
        _handleShared(items);
      });
    } catch (_) {
      // 平台不支持时静默跳过
    }
  }

  Future<void> _handleShared(List<SharedItem> items) async {
    if (items.isEmpty || _handlingShare) return;
    _handlingShare = true;
    try {
      // 先把分享过来的文件复制到应用附件目录
      final attachments = <TaskAttachment>[];
      String title = '';
      for (final item in items) {
        if (title.isEmpty && (item.text?.trim().isNotEmpty ?? false)) {
          title = item.text!.trim();
        }
        final path = item.path;
        if (path != null) {
          final copied = await copyToAttachments(path, item.name ?? '分享的文件');
          if (copied != null) attachments.add(copied);
        }
      }

      // 切到「待办」页，再弹出新建窗口
      jumpToTaskTab();
      await Future.delayed(const Duration(milliseconds: 260));
      final context = Get.context;
      if (context == null) return;

      final now = DateTime.now();
      final end = DateTime(now.year, now.month, now.day, 23, 59);
      final draft = Task(
        endTime: end,
        startTime: end,
        repeatEndsTime: dateOnly(end),
      );
      draft.reset();
      draft.startTime = end;
      draft.endTime = end;
      draft.repeatEndsTime = dateOnly(end);
      draft.summary = title;
      draft.attachments = attachments;

      final res = await showCupertinoModalPopup<Task>(
        context: context,
        builder: (BuildContext context) => TaskCreatePage(draft),
      );
      if (res == null) return;
      if (res.status == TaskStatus.deleted) return;

      final taskList = Get.find<RxList<Task>>(tag: 'taskList');
      taskList.add(res);
      final controller = Get.find<TaskController>();
      controller.updateDeadlineList();
      controller.updateDeadlineListTime();
      controller.taskList.refresh();
    } finally {
      _handlingShare = false;
    }
  }
}
