import 'dart:async';

import 'package:celechron/design/dingtalk_menu.dart';
import 'package:celechron/design/dingtalk_sheet.dart';
import 'package:celechron/mod/ai/ai_compose_sheet.dart';
import 'package:celechron/mod/do_not_disturb.dart';
import 'package:celechron/mod/ai/ai_image.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_alarm_page.dart';
import 'package:celechron/page/task/task_create_page.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/utils/attachment_helper.dart';
import 'package:celechron/utils/share_receiver.dart';
import 'package:celechron/utils/task_alarm_center.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
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
    // 冷启动场景：闹钟可能在监听挂上之前就已被触发（全屏通知拉起 App）。
    // ValueNotifier 不会补发旧值，所以这里主动看一眼当前值。
    if (TaskAlarmCenter.current.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onAlarm());
    }
    // 免打扰兜底：若上次专注期间 App 被系统杀掉，手机可能还停在静音档。
    // 这里发现「我们改过却没还原」就立刻还原（用户自己开的免打扰不会被碰）。
    DoNotDisturb.restoreIfStale();
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

  /// 分享进来的是图片时，问一句要不要交给 AI 识别图中内容
  /// 分享进来的是图片时，问一句要不要交给 AI 识别图中内容（钉钉风格菜单）
  Future<bool> _askUseAiForImage(BuildContext context) async {
    await AiConfig.load();
    if (!AiConfig.isReady) return false;
    bool? picked;
    await showDingTalkMenu(
      context,
      title: '要用 AI 识别这张图吗？',
      message: '图里的文字会发送给你配置的模型服务商（默认 DeepSeek）。\n'
          '选「只存附件」就完全不上传，图会作为附件留在待办里。',
      items: [
        DingTalkMenuItem(
          label: 'AI 识别图中内容',
          icon: Icons.auto_awesome,
          onTap: () => picked = true,
        ),
        DingTalkMenuItem(
          label: '只存附件，不上传',
          icon: CupertinoIcons.paperclip,
          onTap: () => picked = false,
        ),
      ],
    );
    return picked == true;
  }

  /// 分享进来的是文字时，问一句要不要交给 AI 整理
  /// 分享进来的是文字时，问一句要不要交给 AI 整理（钉钉风格菜单）
  Future<bool?> _askUseAi(BuildContext context, String text) async {
    await AiConfig.load();
    if (!AiConfig.isReady) return null;
    bool? picked;
    await showDingTalkMenu(
      context,
      title: '要用 AI 整理这条分享吗？',
      message: text.length > 60 ? '${text.substring(0, 60)}…' : text,
      items: [
        DingTalkMenuItem(
          label: 'AI 整理成待办',
          icon: Icons.auto_awesome,
          onTap: () => picked = true,
        ),
        DingTalkMenuItem(
          label: '直接新建',
          icon: CupertinoIcons.pencil,
          onTap: () => picked = false,
        ),
      ],
    );
    return picked;
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

      // 切到「待办」页
      jumpToTaskTab();
      await Future.delayed(const Duration(milliseconds: 260));
      final context = Get.context;
      if (context == null) return;

      // ===== MOD: 先问一句「新建」还是「加到已有待办」=====
      //
      // 以前分享进来只能新建一条待办 —— 但"把这张图/这个文件补到已有的那件事上"
      // 是很常见的诉求（比如往「写报告」里丢一份参考资料），所以加一个去向选择。
      final target = await showDingTalkSheet<_ShareTarget>(
        context: context,
        title: '分享到 Elychron',
        subtitle: _shareSummary(title, attachments.length),
        options: const [
          DingTalkSheetOption(
            label: '新建待办',
            subtitle: '把分享的内容做成一条新待办（可继续用 AI 整理）',
            value: _ShareTarget.create,
          ),
          DingTalkSheetOption(
            label: '添加到已有待办',
            subtitle: '作为附件与描述追加到某条待办上',
            value: _ShareTarget.attach,
          ),
        ],
      );
      if (target == null || !context.mounted) return;

      if (target == _ShareTarget.attach) {
        await _attachToExistingTask(context, title, attachments);
        return;
      }

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

      // ===== MOD: 分享进来的图片可以交给 AI 识别（截图转待办）=====
      final imagePaths = <String>[];
      for (final attachment in attachments) {
        if (AiImage.looksLikeImage(attachment.path)) {
          imagePaths.add(attachment.path);
        }
      }

      if (imagePaths.isNotEmpty && await _askUseAiForImage(context)) {
        final aiDraft = await showAiComposeSheet(
          context,
          imagePaths: imagePaths,
          initialText: title,
        );
        if (aiDraft != null) {
          aiDraft.applyTo(draft);
          // 原文别丢：AI 没给描述时就把分享附带的文字放进描述
          if (draft.description.trim().isEmpty && title.isNotEmpty) {
            draft.description = title;
          }
        }
      } else if (title.length >= 12 && attachments.isEmpty) {
        // 纯文字分享：问一句要不要交给 AI 整理
        final useAi = await _askUseAi(context, title);
        if (useAi == true) {
          final aiDraft = await showAiComposeSheet(context, initialText: title);
          if (aiDraft != null) {
            aiDraft.applyTo(draft);
            // 原文别丢：AI 没给描述时就把原文放进描述
            if (draft.description.trim().isEmpty) {
              draft.description = title;
            }
          }
        }
      }

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

  /// 分享内容的一句话摘要（弹层副标题）
  static String _shareSummary(String text, int fileCount) {
    final parts = <String>[];
    if (fileCount > 0) parts.add('$fileCount 个文件');
    if (text.trim().isNotEmpty) parts.add('一段文字');
    return parts.isEmpty ? '没有可识别的内容' : '收到 ${parts.join(' 与 ')}';
  }

  /// 把分享内容（附件 + 文字）追加到用户选中的那条待办上。
  Future<void> _attachToExistingTask(
    BuildContext context,
    String text,
    List<TaskAttachment> attachments,
  ) async {
    final all = Get.find<RxList<Task>>(tag: 'taskList');
    // 只列「还活着」的待办，按「进行中优先、截止时间近的靠前」排
    final candidates = all
        .where((task) =>
            task.status != TaskStatus.deleted &&
            task.status != TaskStatus.completed)
        .toList()
      ..sort((a, b) {
        final aRunning = a.status == TaskStatus.running ? 0 : 1;
        final bRunning = b.status == TaskStatus.running ? 0 : 1;
        if (aRunning != bRunning) return aRunning - bRunning;
        return a.endTime.compareTo(b.endTime);
      });

    if (candidates.isEmpty) {
      await showDingTalkPanel(
        context: context,
        title: '没有可添加的待办',
        subtitle: '当前没有进行中的待办',
        children: const [
          DingTalkPanelNote('先新建一条，下次分享时再选「添加到已有待办」。'),
        ],
      );
      return;
    }

    // 太多条就截断：列表弹层不是用来翻页的
    const limit = 15;
    final shown = candidates.take(limit).toList();
    final picked = await showDingTalkSheet<Task>(
      context: context,
      title: '添加到哪条待办',
      subtitle: shown.length < candidates.length
          ? '按截止时间排序，只列出前 $limit 条'
          : '进行中的排在前面；同组按截止时间由近到远',
      options: [
        for (final task in shown)
          DingTalkSheetOption(
            label: task.summary.trim().isEmpty ? '(无标题)' : task.summary.trim(),
            subtitle: _taskLine(task),
            value: task,
          ),
      ],
    );
    if (picked == null || !context.mounted) return;

    if (attachments.isNotEmpty) {
      picked.attachments = <TaskAttachment>[
        ...picked.attachments,
        ...attachments,
      ];
    }
    final incoming = text.trim();
    if (incoming.isNotEmpty) {
      final old = picked.description.trim();
      picked.description = old.isEmpty ? incoming : '$old\n$incoming';
    }
    picked.updatedAt = DateTime.now();

    // 落库（走控制器：它会写 taskList + 更新时间）并刷新界面
    final controller = Get.find<TaskController>();
    controller.updateDeadlineListTime();
    controller.updateDeadlineList();
    controller.taskList.refresh();

    if (!context.mounted) return;
    await showDingTalkPanel(
      context: context,
      title: '已添加到待办',
      children: [
        DingTalkInfoRow(
          label: '待办',
          value:
              picked.summary.trim().isEmpty ? '(无标题)' : picked.summary.trim(),
        ),
        DingTalkInfoRow(label: '附件', value: '共 ${picked.attachments.length} 个'),
      ],
      primaryLabel: '好',
      onPrimary: () => Navigator.of(context).pop(),
    );
  }

  /// 待办选择行下面那行小字：类型 + 时间
  static String _taskLine(Task task) {
    String two(int v) => v.toString().padLeft(2, '0');
    final when = task.isMemo
        ? '无时间'
        : '${task.endTime.month}月${task.endTime.day}日 '
            '${two(task.endTime.hour)}:${two(task.endTime.minute)}';
    final kind = switch (task.type) {
      TaskType.deadline => '截止',
      TaskType.fixed => '活动',
      TaskType.fixedlegacy => '日程',
      TaskType.remind => '提醒',
      TaskType.memo => '备忘',
    };
    return '$kind · $when';
  }
}

/// 分享内容往哪儿去
enum _ShareTarget { create, attach }
