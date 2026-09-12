import 'package:celechron/design/custom_decoration.dart';
import 'package:celechron/design/dingtalk_menu.dart';
import 'package:celechron/design/tag_manager.dart';
import 'package:celechron/design/task_filter_sheets.dart';
import 'package:celechron/design/task_priority_color.dart';
import 'package:celechron/page/flow/flow_controller.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/utils/task_complete.dart';
import 'package:celechron/utils/utils.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/period.dart';
import 'task_create_page.dart';
import 'task_edit_page.dart';
import 'dart:async';
import 'package:get/get.dart';

class TaskPage extends StatelessWidget {
  TaskPage({super.key});

  final _taskController = Get.put(TaskController());
  final _flowController = Get.put(FlowController());

  Future<void> showCardDialog(BuildContext context, Task deadline) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text(
            '${deadline.summary}：${deadline.type == TaskType.deadline ? deadlineStatusName[deadline.status]! : (taskKindName[deadline.type] ?? '')}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ===== P1：时间行随类型变化 =====
                  if (deadline.isEvent) ...[
                    Text(
                      '开始于 ${toStringHumanReadable(deadline.startTime)}',
                    ),
                    Text(
                      '结束于 ${toStringHumanReadable(deadline.endTime)}',
                    ),
                  ],
                  if (deadline.isRemind) ...[
                    Text(
                      '提醒于 ${toStringHumanReadable(deadline.reminderTargetTime)}',
                    ),
                  ],
                  if (deadline.type == TaskType.deadline) ...[
                    Text(
                      '截止于 ${toStringHumanReadable(deadline.endTime)}${deadline.isOverdue ? ' - 已过期' : ''}',
                    ),
                  ],
                  if (deadline.isMemo) ...[
                    const Text('备忘：没有时间，也不会过期'),
                  ],
                  if (deadline.location.isNotEmpty) ...[
                    Text(
                      '地点：${deadline.location}',
                    ),
                  ],
                  if (deadline.description.isNotEmpty) ...[
                    Text(
                      '说明：${deadline.description}',
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
            // 待办 / 提醒 / 备忘 都能标记完成；活动（日程）不按"完成"算
            if (!deadline.isEvent)
              CupertinoDialogAction(
                onPressed: () async {
                  if (deadline.status != TaskStatus.completed) {
                    // 有没勾完的子待办时先确认
                    if (!await confirmCompleteTask(context, deadline)) return;
                    deadline.status = TaskStatus.completed;
                  } else {
                    deadline.status = TaskStatus.running;
                  }
                  _taskController.updateDeadlineListTime();
                  _taskController.taskList.refresh();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(
                    '标记为${deadline.status == TaskStatus.completed ? '未' : ''}完成'),
              ),
            if (deadline.type == TaskType.deadline &&
                (deadline.status == TaskStatus.running ||
                    deadline.status == TaskStatus.suspended))
              CupertinoDialogAction(
                onPressed: () {
                  if (deadline.status == TaskStatus.running) {
                    deadline.status = TaskStatus.suspended;
                  } else {
                    deadline.status = TaskStatus.running;
                  }
                  _taskController.updateDeadlineListTime();
                  _taskController.taskList.refresh();
                  Navigator.of(context).pop();
                },
                child:
                    Text(deadline.status == TaskStatus.running ? '暂停' : '继续'),
              ),
            // 四类都进得了详情页（只有内部的《过去日程》不进）
            if (deadline.type != TaskType.fixedlegacy)
              CupertinoDialogAction(
                onPressed: () async {
                  Navigator.of(context).pop();
                  Task res = await showCupertinoModalPopup(
                        context: context,
                        builder: (BuildContext context) {
                          return TaskEditPage(deadline);
                        },
                      ) ??
                      deadline;
                  bool needUpdate = deadline.differentForFlow(res);
                  deadline.copy(res);
                  _taskController.updateDeadlineList();
                  if (needUpdate) {
                    _taskController.updateDeadlineListTime();
                  }
                  _taskController.taskList.refresh();
                  // 仅改 summary 等字段时 updateDeadlineList 检测不到变化，需显式落盘
                  _taskController.saveDeadlineListToDb();
                },
                child: const Text('编辑'),
              ),
            if (deadline.type == TaskType.fixedlegacy)
              CupertinoDialogAction(
                onPressed: () async {
                  Navigator.of(context).pop();
                  deadline.status = TaskStatus.deleted;
                  _taskController.updateDeadlineList();
                  _taskController.taskList.refresh();
                },
                child: const Text('删除'),
              ),
          ],
        );
      },
    );
  }

  Future<void> newDeadline(context) async {
    DateTime time = DateTime.now();
    Task? deadline = Task(
      endTime: time,
      startTime: time,
      repeatEndsTime: time,
    );
    deadline.reset();
    Task? res = await showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) {
        return TaskCreatePage(deadline);
      },
    );
    if (res != null && res.status != TaskStatus.deleted) {
      _taskController.taskList.add(res);
      _taskController.updateDeadlineList();
      _taskController.updateDeadlineListTime();
      _taskController.taskList.refresh();
    }
  }

  /// 卡片上直接打钩完成 / 取消完成（待办与日程都支持）。
  Future<void> _toggleDone(BuildContext context, Task task) async {
    if (task.status == TaskStatus.completed) {
      task.status = TaskStatus.running;
    } else {
      // 有没勾完的子待办时先确认，确认后一起勾上
      if (!await confirmCompleteTask(context, task)) return;
      task.status = TaskStatus.completed;
    }
    _taskController.updateDeadlineList();
    _taskController.updateDeadlineListTime();
    _taskController.taskList.refresh();
  }

  /// 卡片上子待办那一行的文案。
  ///
  /// 行程型（有任何一步带时间）直接显示**下一步** —— 「下一步 17:50 探鱼吃饭」，
  /// 比光秃秃一句「子待办 0/3」有用得多；清单型还是老样子。
  String _subtaskSummary(Task task) {
    final next = task.nextItineraryStep;
    if (next != null) {
      final anchor = next.anchorTime!;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(anchor.year, anchor.month, anchor.day);
      final hh = anchor.hour.toString().padLeft(2, '0');
      final mm = anchor.minute.toString().padLeft(2, '0');
      final prefix =
          day == today ? '$hh:$mm' : '${anchor.month}-${anchor.day} $hh:$mm';
      final title = next.title.isEmpty ? '(未命名)' : next.title;
      return ' 下一步 $prefix $title';
    }
    final count = '${task.subtaskDoneCount}/${task.subtasks.length}';
    return task.hasUnfinishedSubtasks ? ' 子待办 $count 没做完' : ' 子待办 $count';
  }

  /// 卡片上的一行时间信息（图标 + 文案），四类语义共用同一套样式。
  /// 批量删除前的二次确认。
  ///
  /// 顺手把条数写在标题里（「删除 8 条已完成的待办？」）—— 批量操作最怕的是
  /// 不知道自己会删掉多少。没有可删的就不问，直接什么都不做。
  Future<bool> _confirmBulkDelete(
    BuildContext context,
    String what,
    int count,
  ) async {
    if (count <= 0) return false;
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: Text('删除 $count 条$what？'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('删除后无法撤销。', style: TextStyle(fontSize: 14)),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 划过删除前的二次确认。
  ///
  /// 顺手把「会一起删掉什么」说清楚 —— 待办是连子待办/评论/附件一起走的，
  /// 只说「删除待办？」用户不知道代价。
  Future<bool> _confirmDelete(BuildContext context, Task task) async {
    final name =
        task.summary.trim().isEmpty ? '(未命名待办)' : task.summary.trim();
    final extras = <String>[
      if (task.subtasks.isNotEmpty) '${task.subtasks.length} 个子待办',
      if (task.comments.isNotEmpty) '${task.comments.length} 条评论',
      if (task.attachments.isNotEmpty) '${task.attachments.length} 个附件',
    ];
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('删除这条待办？'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '「$name」${extras.isEmpty ? '' : '（含 ${extras.join('、')}）'}\n删除后无法撤销。',
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
            child: const Text('删除'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _cardTimeRow(BuildContext context, IconData icon, String text) {
    final baseColor =
        CupertinoTheme.of(context).textTheme.textStyle.color ?? CupertinoColors.label;
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: baseColor.withValues(alpha: 0.5),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: baseColor.withValues(alpha: 0.75),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget createCard(context, Task deadline, Color color, String? title) {
    return Column(
      children: [
        title == null
            ? const SizedBox(height: 0)
            : SubtitleRow(subtitle: title),
        Dismissible(
          key: Key(deadline.uid),
          direction: !deadline.isEvent
              ? DismissDirection.horizontal
              : DismissDirection.endToStart,
          movementDuration: const Duration(milliseconds: 300),
          resizeDuration: const Duration(milliseconds: 300),
          dismissThresholds: const {
            DismissDirection.startToEnd: 0.25,
            DismissDirection.endToStart: 0.25,
          },
          crossAxisEndOffset: 0.0,
          background: !deadline.isEvent
              ? Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 16),
                  decoration: BoxDecoration(
                    color: deadline.status == TaskStatus.completed
                        ? CupertinoColors.systemOrange
                        : CupertinoColors.systemGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: CupertinoColors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      deadline.status == TaskStatus.completed
                          ? CupertinoIcons.arrow_counterclockwise
                          : CupertinoIcons.check_mark_circled_solid,
                      color: CupertinoColors.white,
                      size: 20,
                    ),
                  ),
                )
              : null,
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: CupertinoColors.systemRed,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: CupertinoColors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.delete,
                color: CupertinoColors.white,
                size: 20,
              ),
            ),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              // 向右滑（从左到右）：完成 - 不真正 dismiss，只更新状态
              // 待办 / 提醒 / 备忘 都能滑；活动（日程）不算"完成"
              if (!deadline.isEvent) {
                if (deadline.status == TaskStatus.completed) {
                  // 如果已完成，恢复为未完成状态
                  deadline.status = TaskStatus.running;
                } else {
                  // 有没勾完的子待办时先确认
                  if (!await confirmCompleteTask(context, deadline)) {
                    return false;
                  }
                  deadline.status = TaskStatus.completed;
                }
                _taskController.updateDeadlineList();
                _taskController.updateDeadlineListTime();
                _taskController.taskList.refresh();
              }
              return false; // 阻止真正的 dismiss
            } else if (direction == DismissDirection.endToStart) {
              // 向左滑（从右到左）：删除 —— **必须二次确认**，
              // 手一抖就丢一条待办（连带它的子待办、评论、附件）太狠了
              return await _confirmDelete(context, deadline);
            }
            return false;
          },
          onDismissed: (direction) {
            // 只有删除操作会真正 dismiss
            if (direction == DismissDirection.endToStart) {
              // 向左滑（从右到左）：删除
              deadline.status = TaskStatus.deleted;
              _taskController.updateDeadlineList();
              _taskController.updateDeadlineListTime();
              _taskController.taskList.refresh();
            }
          },
          child: RoundRectangleCard(
            onTap: () async {
              // 直接导航到编辑页面
              Task? res = await Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (context) => TaskEditPage(deadline),
                ),
              );
              if (res != null) {
                // 详情页里点了「删除任务」：这里必须真的把它标成已删除
                if (res.status == TaskStatus.deleted) {
                  deadline.status = TaskStatus.deleted;
                } else {
                  deadline.copy(res);
                }
                _taskController.updateDeadlineList();
                _taskController.updateDeadlineListTime();
                _taskController.taskList.refresh();
              }
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 36),
                        onPressed: () => _toggleDone(context, deadline),
                        child: Icon(
                          deadline.status == TaskStatus.completed
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 22,
                          color: deadline.status == TaskStatus.completed
                              ? CupertinoColors.systemGreen
                              : CupertinoDynamicColor.resolve(
                                  CupertinoColors.tertiaryLabel, context),
                        ),
                      ),
                      Container(
                        width: 12.0,
                        height: 12.0,
                        decoration: customDecoration(
                          color: color,
                          shape: periodTypeShape[PeriodType.user]!,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                          flex: 4,
                          child: Text(deadline.summary,
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .textStyle
                                  .copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    overflow: TextOverflow.ellipsis,
                                  ))),
                      const Spacer(),
                      // ===== P1：状态文案随类型变化 =====
                      // 截止看状态；活动看时间轴；提醒型只是"响过没有"；备忘不显示
                      Obx(() {
                        final now = _flowController.timeNow.value;
                        final String label;
                        if (deadline.type == TaskType.deadline) {
                          label = deadlineStatusName[deadline.status]!;
                        } else if (deadline.isRemind) {
                          label =
                              now.isBefore(deadline.endTime) ? '待提醒' : '已提醒';
                        } else if (deadline.isMemo) {
                          label = deadline.status == TaskStatus.completed
                              ? '完成'
                              : '备忘';
                        } else {
                          label = now.isBefore(deadline.startTime)
                              ? '未开始'
                              : (!now.isBefore(deadline.endTime)
                                  ? '已结束'
                                  : '进行中');
                        }
                        return Text(
                            label,
                            style: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  overflow: TextOverflow.ellipsis,
                                ));
                      }),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  // ===== P1：时间行随类型变化 =====
                  // 活动两行（开始/结束）、截止一行、提醒一行、备忘一行都不显示
                  if (deadline.isRemind) ...[
                    _cardTimeRow(
                      context,
                      CupertinoIcons.bell,
                      ' 提醒于：${toStringHumanReadable(deadline.reminderTargetTime)}',
                    ),
                  ] else if (!deadline.isMemo) ...[
                    _cardTimeRow(
                      context,
                      CupertinoIcons.time_solid,
                      deadline.isEvent
                          ? ' 开始于：${toStringHumanReadable(deadline.startTime)}'
                          : ' 截止于：${toStringHumanReadable(deadline.endTime)}${deadline.isOverdue ? ' - 已过期' : ''}',
                    ),
                    if (deadline.isEvent)
                      _cardTimeRow(
                        context,
                        CupertinoIcons.time,
                        ' 结束于：${toStringHumanReadable(deadline.endTime)}',
                      ),
                    // 设过提醒就把提醒时刻也写出来（活动锚开始、截止锚截止）
                    if (deadline.schedulesReminder)
                      _cardTimeRow(
                        context,
                        CupertinoIcons.bell_fill,
                        ' 提醒：${toStringHumanReadable(deadline.reminderTargetTime)}',
                      ),
                  ],
                  if (deadline.location.isNotEmpty) ...[
                    Row(children: [
                      Icon(
                        CupertinoIcons.location_solid,
                        size: 14,
                        color: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .color!
                            .withValues(alpha: 0.5),
                      ),
                      Expanded(
                          child: Text(' 地点：${deadline.location}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle
                                    .color!
                                    .withValues(alpha: 0.75),
                                overflow: TextOverflow.ellipsis,
                              )))
                    ]),
                  ],
                  if (deadline.subtasks.isNotEmpty ||
                      deadline.priority != TaskPriority.normal) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (deadline.priority != TaskPriority.normal) ...[
                          Icon(
                            CupertinoIcons.flag_fill,
                            size: 14,
                            color: taskPriorityColor(deadline.priority),
                          ),
                          Text(
                            ' ${taskPriorityName[deadline.priority]!}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: taskPriorityColor(deadline.priority),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (deadline.subtasks.isNotEmpty) ...[
                          Icon(
                            CupertinoIcons.list_bullet,
                            size: 14,
                            // 活动结束了还有没做完的子待办：红一下提个醒
                            color: deadline.hasUnfinishedSubtasks
                                ? CupertinoColors.systemRed
                                : CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle
                                    .color!
                                    .withValues(alpha: 0.5),
                          ),
                          Expanded(
                            child: Text(
                              // ===== P2：行程型直接告诉用户「下一步」是什么 =====
                              _subtaskSummary(deadline),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: deadline.hasUnfinishedSubtasks
                                    ? CupertinoColors.systemRed
                                    : CupertinoTheme.of(context)
                                        .textTheme
                                        .textStyle
                                        .color!
                                        .withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: const Text('待办'),
              border: null,
              stretch: true,
              bottomMode: NavigationBarBottomMode.always,
              // 分类标签页贴在标题下方，间距更紧凑
              bottom: PreferredSize(
                // 高度跟着系统字号走，避免大字号时标签行顶到下面的筛选行；
                // 留白压到最小，让下面的胶囊整体上移
                preferredSize: Size.fromHeight(
                    MediaQuery.textScalerOf(context).scale(15) + 14),
                child: _buildTabs(context),
              ),
              trailing: // Two buttons in the nav bar.
                  Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 专注入口已经独立成底部「专注」标签页，这里不再重复放图标

                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(
                      CupertinoIcons.add_circled,
                      semanticLabel: 'Add',
                    ),
                    onPressed: () async {
                      await newDeadline(context);
                      _taskController.updateDeadlineList();
                      _taskController.taskList.refresh();
                    },
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(
                      CupertinoIcons.ellipsis_circle,
                      semanticLabel: 'More',
                    ),
                    onPressed: () async {
                      await showDingTalkMenu(
                        context,
                        items: [
                          DingTalkMenuItem(
                            label: '删除已完成待办',
                            icon: CupertinoIcons.checkmark_circle,
                            onTap: () async {
                              // 批量删除比单条滑动更需要确认：一次可能删掉十几条
                              final count =
                                  _taskController.doneDeadlineList.length;
                              if (!await _confirmBulkDelete(
                                  context, '已完成的待办', count)) {
                                return;
                              }
                              _taskController.removeCompletedDeadline(context);
                              _taskController.updateDeadlineList();
                              _taskController.taskList.refresh();
                            },
                          ),
                          DingTalkMenuItem(
                            label: '删除已过期待办',
                            icon: CupertinoIcons.clock,
                            onTap: () async {
                              final count = _taskController.taskList
                                  .where((t) => t.status == TaskStatus.failed)
                                  .length;
                              if (!await _confirmBulkDelete(
                                  context, '已过期的待办', count)) {
                                return;
                              }
                              _taskController.removeFailedDeadline(context);
                              _taskController.updateDeadlineList();
                              _taskController.taskList.refresh();
                            },
                          ),
                          DingTalkMenuItem(
                            label: '暂停所有待办',
                            icon: CupertinoIcons.pause_circle,
                            onTap: () {
                              if (_taskController.suspendAllDeadline(context) >
                                  0) {
                                _taskController.updateDeadlineListTime();
                                _taskController.taskList.refresh();
                              }
                            },
                          ),
                          DingTalkMenuItem(
                            label: '继续所有待办',
                            icon: CupertinoIcons.play_circle,
                            onTap: () {
                              if (_taskController.continueAllDeadline(context) >
                                  0) {
                                _taskController.updateDeadlineListTime();
                                _taskController.taskList.refresh();
                              }
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            _buildFilterRow(context),
            _buildTagRow(context),
            Obx(
              () {
                final list = _taskController.visibleTaskList;
                if (list.isEmpty) {
                  return SliverToBoxAdapter(
                    child: SizedBox(
                      height: 320,
                      child: Column(
                        children: [
                          const Spacer(),
                          Text(
                            '没有待办',
                            style:
                                CupertinoTheme.of(context).textTheme.textStyle,
                            textAlign: TextAlign.center,
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final task = list[index];
                      return Container(
                        padding: EdgeInsets.only(
                          top: index == 0 ? 4 : 5,
                          bottom: 5,
                          left: 16,
                          right: 16,
                        ),
                        child: createCard(context, task,
                            UidColors.colorFromUid(task.uid), null),
                      );
                    },
                    childCount: list.length,
                  ),
                );
              },
            ),
            SliverToBoxAdapter(
              child: Container(
                height: 100,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- 标签页 / 分类行

  Widget _buildTabs(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    return Obx(
      () => Container(
        // 不要背景色，避免标题下方出现一条灰带
        color: CupertinoColors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(
          // 两端对齐 + 等距分布，四个分类的间隔看起来一致
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(TaskController.tabNames.length, (index) {
            final selected = _taskController.selectedTab.value == index;
            final count = _taskController.tabCount(index);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _taskController.selectedTab.value = index,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        TaskController.tabNames[index],
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w400,
                          color: selected ? textColor : labelColor,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: index == 1
                                ? CupertinoColors.systemOrange
                                : CupertinoColors.systemBlue,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                                fontSize: 11, color: CupertinoColors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 3,
                    width: 22,
                    decoration: BoxDecoration(
                      color: selected
                          ? CupertinoColors.systemBlue
                          : CupertinoColors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
    IconData? icon,
    Color? dotColor,
  }) {
    final color = active
        ? CupertinoColors.systemBlue
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? CupertinoColors.systemBlue.withValues(alpha: 0.08)
              : CupertinoDynamicColor.resolve(
                  CupertinoColors.tertiarySystemFill, context),
          borderRadius: BorderRadius.circular(16),
          border: active
              ? Border.all(color: CupertinoColors.systemBlue, width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
            ],
            Text(label, style: TextStyle(fontSize: 14, color: color)),
            const SizedBox(width: 3),
            Icon(CupertinoIcons.chevron_down, size: 11, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow(BuildContext context) {
    return SliverToBoxAdapter(
      child: Obx(
        () => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 3),
          child: Row(
            children: [
              // 「全部分类」已删除：它只是「清空标签筛选」，而标签行里
              // 再点一下选中的标签就能取消，位置又被「全部类型」取代了。
              _filterChip(
                context,
                label: _taskController.kindFilterLabel,
                icon: CupertinoIcons.square_grid_2x2,
                active: _taskController.filterKinds.isNotEmpty,
                onTap: () => showKindFilterSheet(context, _taskController),
              ),
              const SizedBox(width: 8),
              _filterChip(
                context,
                label: taskSortLabel(_taskController.sortKey.value),
                active: true,
                onTap: () => showSortSheet(context, _taskController),
              ),
              const SizedBox(width: 8),
              _filterChip(
                context,
                label: '筛选',
                icon: CupertinoIcons.line_horizontal_3_decrease,
                active: _taskController.hasActiveFilters,
                onTap: () => showFilterSheet(context, _taskController),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 第二行：标签管理入口 + 所有标签（图五）
  Widget _buildTagRow(BuildContext context) {
    return SliverToBoxAdapter(
      child: Obx(
        () {
          // 依赖 tagVersion 让标签库增删后能刷新
          _taskController.tagVersion.value;
          final tags = _taskController.allTags;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 3, 16, 6),
            child: Row(
              children: [
                _filterChip(
                  context,
                  label: '标签管理',
                  icon: CupertinoIcons.tag,
                  active: false,
                  onTap: () => showTagManager(
                    context,
                    onChanged: () {
                      _taskController.tagVersion.value++;
                      // 标签被删掉后，同步清掉它的筛选状态
                      final tags = _taskController.allTags;
                      _taskController.selectedTags
                          .removeWhere((tag) => !tags.contains(tag));
                    },
                  ),
                ),
                // 选中了标签才出现：一键把标签筛选全清掉
                // （原来这件事是「全部分类」那枚 chip 干的，它已经删掉了）
                if (_taskController.selectedTags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _filterChip(
                      context,
                      label: '清除标签筛选',
                      icon: CupertinoIcons.xmark_circle,
                      active: true,
                      onTap: _taskController.selectedTags.clear,
                    ),
                  ),
                ...tags.map((tag) {
                  final active = _taskController.selectedTags.contains(tag);
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _filterChip(
                      context,
                      label: tag,
                      dotColor: tagColorOf(tag),
                      active: active,
                      onTap: () {
                        // 多选：点一下加进来，再点一下移出去
                        if (active) {
                          _taskController.selectedTags.remove(tag);
                        } else {
                          _taskController.selectedTags.add(tag);
                        }
                      },
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TaskPageColors {
  static const List<CupertinoDynamicColor> taskMarkColors = [
    spring,
    summer,
    winter,
    violet,
    sakura,
    cyan,
    magenta,
    peach,
    okGreen,
  ];

  static const CupertinoDynamicColor spring =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 255, 226, 1.0),
    darkColor: Color.fromRGBO(147, 251, 56, 1.0),
  );

  static const CupertinoDynamicColor summer =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 218, 238, 1.0),
    darkColor: Color.fromRGBO(255, 25, 69, 1.0),
  );

  static const CupertinoDynamicColor autumn =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 234, 230, 1.0),
    darkColor: Color.fromRGBO(255, 101, 56, 1.0),
  );

  static const CupertinoDynamicColor winter =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(226, 239, 255, 1.0),
    darkColor: Color.fromRGBO(0, 183, 251, 1.0),
  );

  static const CupertinoDynamicColor violet =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 229, 255, 1.0),
    darkColor: Color.fromRGBO(151, 131, 216, 1.0),
  );

  static const CupertinoDynamicColor sakura =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 226, 255, 1.0),
    darkColor: Color.fromRGBO(218, 130, 217, 1.0),
  );

  static const CupertinoDynamicColor sand =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 246, 211, 1.0),
    darkColor: Color.fromRGBO(252, 222, 59, 1.0),
  );

  static const CupertinoDynamicColor cyan =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(218, 234, 255, 1.0),
    darkColor: Color.fromRGBO(0, 140, 255, 1.0),
  );

  static const CupertinoDynamicColor magenta =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 229, 255, 1.0),
    darkColor: Color.fromRGBO(238, 55, 161, 1.0),
  );

  static const CupertinoDynamicColor peach =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(255, 235, 226, 1.0),
    darkColor: Color.fromRGBO(233, 114, 70, 1.0),
  );

  static const CupertinoDynamicColor okGreen =
      CupertinoDynamicColor.withBrightness(
    color: Color.fromRGBO(230, 255, 226, 1.0),
    darkColor: Color.fromRGBO(63, 222, 23, 1.0),
  );
}
