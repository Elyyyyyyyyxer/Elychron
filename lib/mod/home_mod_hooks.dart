import 'dart:async';

import 'package:celechron/design/dingtalk_menu.dart';
import 'package:celechron/design/dingtalk_sheet.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/mod/ai/ai_compose_sheet.dart';
import 'package:celechron/mod/do_not_disturb.dart';
import 'package:celechron/mod/focus_runtime.dart';
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
import 'package:celechron/worker/todo_widget_messenger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:get/get.dart';
import 'package:celechron/page/option/option_controller.dart';
import 'package:celechron/platform/desktop_notify.dart';
import 'package:celechron/tutorial/tutorial_entry.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:celechron/tutorial/tutorial_model.dart';
import 'package:celechron/tutorial/tutorial_router.dart';

/// ============ 首页的魔改钩子：分享接收 + 闹钟弹出 ============
///
/// 上游的 `lib/page/home_page.dart` 在持续重构（1.3 就把标签机制整个换成了
/// PageView + _KeepAlivePage），所以魔改逻辑不塞在那个文件里，
/// 而是集中在这里；首页只保留 3 行挂载（见 `// ===== MOD =====` 标记）。
class HomeModHooks {
  HomeModHooks({
    required this.jumpToTaskTab,
    required this.jumpToTab,
  });

  /// 切到待办标签页（首页那边是 _pageController.jumpToPage(1)）
  final void Function() jumpToTaskTab;

  /// 切到任意底部标签（教程的"去试试"按钮要用）
  final void Function(int index) jumpToTab;

  StreamSubscription<List<SharedItem>>? _shareSubscription;
  bool _handlingShare = false;
  bool _handlingWidgetAction = false;

  void start() {
    TaskAlarmCenter.current.addListener(_onAlarm);
    TodoWidgetActionCenter.current.addListener(_onTodoWidgetAction);
    _listenShares();
    // 冷启动场景：闹钟可能在监听挂上之前就已被触发（全屏通知拉起 App）。
    // ValueNotifier 不会补发旧值，所以这里主动看一眼当前值。
    if (TaskAlarmCenter.current.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onAlarm());
    }
    // 免打扰兜底：若上次专注期间 App 被系统杀掉，手机可能还停在静音档。
    // 这里发现我们改过却没还原就立刻还原（用户自己开的免打扰不会被碰）。
    DoNotDisturb.restoreIfStale();
    // 一次性迁移：把异步刷新改成默认开启（老用户也会被迁移一次）。
    _migrateOnce();
    // 补记上次登录的账号密码：老用户是在这个功能之前登录的，
    // 不补的话他们一退出登录就没得预填。控制器可能还没注册，所以延后再试一次。
    _backfillRememberedAccount();
    Future<void>.delayed(
        const Duration(seconds: 3), _backfillRememberedAccount);
    // 教程里的去试试按钮要能跳到对应页面（映射集中在这里，教程内容保持纯数据）
    _wireTutorialRouter();
    // 从没进过教程中心的新用户：第一帧之后引一句"这里有教程"（只弹一次）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = Get.context;
      if (context != null) promptTutorialIntroOnce(context);
    });
    // 桌面小组件（PR #4）：冷启动也可能是从小组件点进来的，
    // ValueNotifier 不会补发旧值，所以这里也主动看一眼当前值。
    if (TodoWidgetActionCenter.current.value != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _onTodoWidgetAction());
    }
  }

  /// 把教程的行动按钮接到真实的页面跳转上
  void _wireTutorialRouter() {
    TutorialRouter.instance.handler = (TutorialTarget target) {
      switch (target) {
        case TutorialTarget.taskList:
          jumpToTaskTab();
        case TutorialTarget.calendar:
          _jumpToTab(0); // 日程
        case TutorialTarget.focus:
          _jumpToTab(2); // 专注
        case TutorialTarget.settings:
        case TutorialTarget.dataSection:
        case TutorialTarget.aiSettings:
          _jumpToTab(4); // 设置（数据/教程/AI 都在设置里）
      }
    };
  }

  /// 切到某个底部标签（索引与 `home_page.dart` 的 PageView 顺序一致：
  /// 0 日程 / 1 待办 / 2 专注 / 3 学业 / 4 设置）
  void _jumpToTab(int index) => jumpToTab(index);

  /// 把当前已登录的账号密码补记一份，供退出后预填（幂等）
  void _backfillRememberedAccount() {
    try {
      if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return;
      if (!Get.isRegistered<OptionController>(tag: 'optionController')) return;
      final scholar =
          Get.find<OptionController>(tag: 'optionController').scholar.value;
      final username = scholar.username ?? '';
      final password = scholar.password ?? '';
      if (username.isEmpty && password.isEmpty) return;
      final db = Get.find<DatabaseHelper>(tag: 'db');
      db.rememberedAccount().then((saved) {
        // 已经有记录就不覆盖（避免把用户后来改过的密码冲掉）
        if (saved.username.isEmpty && saved.password.isEmpty) {
          db.rememberAccount(username, password);
        }
      });
    } catch (_) {
      // 补记失败不影响启动
    }
  }

  /// 启动时跑一次的一次性迁移（带标记键，幂等，失败不影响启动）
  void _migrateOnce() {
    try {
      if (!Get.isRegistered<DatabaseHelper>(tag: 'db')) return;
      Get.find<DatabaseHelper>(tag: 'db').migrateAsyncRefreshDefault();
    } catch (_) {}
  }

  void dispose() {
    TaskAlarmCenter.current.removeListener(_onAlarm);
    TodoWidgetActionCenter.current.removeListener(_onTodoWidgetAction);
    _shareSubscription?.cancel();
  }

  void _onTodoWidgetAction() {
    final action = TodoWidgetActionCenter.current.value;
    if (action == null || _handlingWidgetAction) return;
    TodoWidgetActionCenter.current.value = null;
    unawaited(_handleTodoWidgetAction(action));
  }

  Future<void> _handleTodoWidgetAction(TodoWidgetAction action) async {
    _handlingWidgetAction = true;
    try {
      jumpToTaskTab();
      if (action == TodoWidgetAction.openList) return;

      await Future.delayed(const Duration(milliseconds: 260));
      final context = Get.context;
      if (context == null) return;

      final now = DateTime.now();
      final draft = Task(
        endTime: now,
        startTime: now,
        repeatEndsTime: dateOnly(now),
      )..reset();
      final result = await showCupertinoModalPopup<Task>(
        context: context,
        builder: (context) => TaskCreatePage(draft),
      );
      if (result == null || result.status == TaskStatus.deleted) return;

      final controller = Get.find<TaskController>();
      controller.taskList.add(result);
      controller.updateDeadlineList();
      controller.updateDeadlineListTime();
      controller.taskList.refresh();
    } finally {
      _handlingWidgetAction = false;
      if (TodoWidgetActionCenter.current.value != null) {
        scheduleMicrotask(_onTodoWidgetAction);
      }
    }
  }

  /// 闹钟到点。
  ///
  /// 手机：全屏闹钟页（原来那套，能全屏影响、能循环响铃）。
  /// 桌面：用户拍板的"钉钉 DING 那种"—— 响一下 + 右下角一个弹窗，
  /// 不抢全屏（桌面上抢全屏是很讨厌的行为）。
  void _onAlarm() {
    final task = TaskAlarmCenter.current.value;
    final context = Get.context;
    if (task == null || context == null) return;
    if (PlatformFeatures.isDesktop) {
      DesktopNotify.ding(
        title: task.summary.trim().isEmpty ? '待办提醒' : task.summary.trim(),
        body: task.description.trim().isEmpty
            ? 'Elychron 提醒你处理这条待办'
            : task.description.trim(),
      );
      return;
    }
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
      message: '图片会发送给你配置的模型服务商进行识别。\n'
          '选只存附件会只将图作为附件。',
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

  /// ===== MOD: 专注期间不打断 =====
  ///
  /// 用户反馈：如果在专注期间通过外部分享进入 Elychron，会强行打断并提示未正常退出。
  /// 原因：分享流程会切到待办页并弹出新建面板， 直接压在专注页上，把这次专注打断，
  /// 而专注会话是"未完成"状态，于是再进专注页就会提示"上次没有正常结束"。
  ///
  /// 现在：专注进行中先把分享内容**存起来**，等专注结束再自动弹出来处理。
  final List<SharedItem> _pendingShares = <SharedItem>[];
  Timer? _focusPendingPoll;

  /// 现在**真的**在专注计时吗？
  ///
  /// 2026-09-17 修正：以前这里查的是"库里有没有未结算的会话"，
  /// 而 App 被系统杀掉之后那条会话会**一直留着**，于是分享从此被无限期攒着，
  /// 表现就是"图片分享进来什么都不弹"。现在改成问运行时状态
  /// （只有专注页真的在计时才算，暂停 / App 已死都算没在专注）。
  bool _isFocusRunning() => FocusRuntime.isRunning;

  /// 桌面端：把拖进窗口的文件交给同一条管线（见 lib/page/desktop/desktop_shell.dart）
  ///
  /// 手机是"从别的应用分享进来"，桌面没有那个入口，用户拍板改成**拖文件进窗口**。
  /// 进来之后走的是同一套逻辑（复制到附件目录 → 问新建还是挂到已有待办 →
  /// 图片还能交给 AI 识别），所以这里只做一层转换，不另写一份。
  Future<void> acceptDroppedFiles(List<SharedItem> items) =>
      _handleShared(items);

  Future<void> _handleShared(List<SharedItem> items) async {
    if (items.isEmpty || _handlingShare) return;
    if (_isFocusRunning()) {
      // 专注中：攒着，每 3 秒看一眼是否结束了
      _pendingShares.addAll(items);
      _focusPendingPoll ??= Timer.periodic(const Duration(seconds: 3), (_) {
        if (_isFocusRunning()) return;
        _focusPendingPoll?.cancel();
        _focusPendingPoll = null;
        final pending = List<SharedItem>.from(_pendingShares);
        _pendingShares.clear();
        if (pending.isNotEmpty) _handleShared(pending);
      });
      return;
    }
    _handlingShare = true;
    try {
      // 先把分享过来的文件复制到应用附件目录
      final attachments = <TaskAttachment>[];
      final unreadable = <String>[];
      String title = '';
      for (final item in items) {
        if (title.isEmpty && (item.text?.trim().isNotEmpty ?? false)) {
          title = item.text!.trim();
        }
        if (item.isUnreadable) {
          unreadable.add(item.name ?? '一个文件');
          continue;
        }
        final path = item.path;
        if (path != null) {
          final copied = await copyToAttachments(path, item.name ?? '分享的文件');
          if (copied != null) {
            attachments.add(copied);
          } else {
            unreadable.add(item.name ?? '一个文件');
          }
        }
      }

      // ===== 什么都不剩时**必须说一句**（2026-09-17 用户报的"分享没反应"）=====
      //
      // 以前附件读不出来就被悄悄跳过，items 空了直接 return ——
      // 用户点了分享，App 像是没收到，根本不知道是权限问题。
      if (title.isEmpty && attachments.isEmpty) {
        final context = Get.context;
        if (context == null || !context.mounted) return;
        await showCupertinoDialog<void>(
          context: context,
          builder: (BuildContext context) => CupertinoAlertDialog(
            title: const Text('这个分享读不出来'),
            content: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                unreadable.isEmpty
                    ? '没有收到可用的文字或文件。'
                    : '对方应用没有把${unreadable.length} 个文件的读取权限给过来'
                        '（${unreadable.first}）。\n'
                        '可以先把它保存到相册/文件里，再从 Elychron 里添加。',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('知道了'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
        return;
      }

      // 切到待办页
      jumpToTaskTab();
      await Future.delayed(const Duration(milliseconds: 260));
      final context = Get.context;
      if (context == null) return;

      // ===== MOD: 先问一句新建还是加到已有待办=====
      //
      // 以前分享进来只能新建一条待办， 但"把这张图/这个文件补到已有的那件事上"
      // 是很常见的诉求（比如往写报告里丢一份参考资料），所以加一个去向选择。
      final target = await showDingTalkSheet<_ShareTarget>(
        context: context,
        title: '分享到 Elychron',
        subtitle: unreadable.isEmpty
            ? _shareSummary(title, attachments.length)
            : '${_shareSummary(title, attachments.length)}（有 '
                '${unreadable.length} 个文件读不出来，已跳过）',
        options: const [
          DingTalkSheetOption(
            label: '新建待办',
            subtitle: '把分享的内容做成一条新待办',
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
    // 只列还活着的待办，按进行中优先、截止时间近的靠前排
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
          DingTalkPanelNote('先新建一条，下次分享时再选添加到已有待办。'),
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
