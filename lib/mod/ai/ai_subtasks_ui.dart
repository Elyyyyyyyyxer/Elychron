import 'package:celechron/mod/ai/ai_settings_page.dart';
import 'package:celechron/mod/ai/ai_task_draft.dart';
import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter/cupertino.dart';

/// AI 不可用时的提示；返回是否已经可以继续用 AI。
Future<bool> _ensureAiReady(BuildContext context) async {
  await AiConfig.load();
  if (AiConfig.isReady) return true;
  await showCupertinoDialog<void>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: const Text('还没配置 AI'),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          AiConfig.apiKey.isEmpty
              ? '去「设置 → 智能 → AI 智能助手」填自己的 DeepSeek key 后就能用。'
              : 'AI 功能还没打开，去设置里打开开关即可。',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('好'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          child: const Text('去配置'),
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context, rootNavigator: true).push(
              CupertinoPageRoute<void>(
                builder: (BuildContext context) => const AiSettingsPage(),
              ),
            );
          },
        ),
      ],
    ),
  );
  return false;
}

/// ===== P2 遗留：「AI 补全行程」=====
///
/// 给**已经列好的**清单型子待办补时间与地点：不增删步骤、不改标题，
/// 只往每一步上填它缺的字段。适合「步骤我自己想好了，只是懒得给每步填时间」。
Future<void> runAiFillItinerary(
  BuildContext context,
  Task task, {
  required VoidCallback onChanged,
}) async {
  if (!await _ensureAiReady(context)) return;
  if (!context.mounted) return;
  if (task.subtasks.isEmpty) {
    await _simple(context, '还没有步骤', '先用「AI 拆成子待办」或手动加几步，再来补时间。');
    return;
  }

  showCupertinoDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => const CupertinoAlertDialog(
      content: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(radius: 13),
            SizedBox(height: 14),
            Text('AI 正在补时间…', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    ),
  );

  AiItineraryFill? fill;
  String? failure;
  try {
    fill = await AiTaskDraft.fillItineraryFor(task);
  } on AiException catch (error) {
    failure = error.message;
  } catch (error) {
    failure = '$error';
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // 关掉转圈框

  if (failure != null) {
    await _simple(context, '没能补出来', failure);
    return;
  }
  if (fill == null || fill.isEmpty) {
    await _simple(context, '没补出来', 'AI 没有返回可用的步骤。把待办的标题或描述写具体一点再试。');
    return;
  }
  final current = fill;
  if (current.timedCount == 0 && current.locatedCount == 0) {
    await _simple(
      context,
      '没有可补的内容',
      'AI 没找到任何时间或地点线索。'
      '${current.warnings.isEmpty ? '（原文里确实没提时间时，这是正常的）' : '\n\n${current.warnings.join('\n')}'}',
    );
    return;
  }

  final ok = await _previewFill(context, task, current);
  if (ok != true) return;

  final changed = AiTaskDraft.applyItineraryFill(task, current);
  onChanged();
  if (!context.mounted) return;
  if (!changed) {
    await _simple(context, '没有变化', '补出来的内容与现在一致，什么都没改。');
    return;
  }
  await _simple(
    context,
    '补好了',
    '${current.timedCount} 步补上了时间'
    '${current.locatedCount > 0 ? '，${current.locatedCount} 步补上了地点' : ''}。'
    '${current.warnings.isEmpty ? '' : '\n\n有几处我替你处理了：\n${current.warnings.join('\n')}'}',
  );
}

/// 预览：左边是原来的步骤，下面写这次要补上的内容
Future<bool?> _previewFill(
  BuildContext context,
  Task task,
  AiItineraryFill fill,
) {
  final labelColor =
      CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
  return showCupertinoDialog<bool>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: const Text('这些步骤会补上时间'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0;
                i < fill.steps.length && i < task.subtasks.length;
                i++) ...[
              Text(
                '${i + 1}. ${task.subtasks[i].title}',
                style: const TextStyle(fontSize: 14),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 6),
                child: Text(
                  [
                    if (fill.steps[i].timeLabel.isNotEmpty)
                      '补时间：${fill.steps[i].timeLabel}',
                    if (fill.steps[i].location.isNotEmpty)
                      '补地点：${fill.steps[i].location}',
                    if (!fill.steps[i].hasTime && fill.steps[i].location.isEmpty)
                      '这一步没有可用线索，保持原样',
                  ].join('　'),
                  style: TextStyle(fontSize: 12, color: labelColor),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('取消'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          child: const Text('就用这些'),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
}

/// 「AI 拆成子待办」的界面流程。
///
/// 刻意放在这里而不是塞进 `task_edit_page.dart`：那个文件以后跟上游合并时能少改一点。
/// 详情页只需要在 ⋯ 菜单里加一项、调一次 [runAiSubtasks]。
Future<void> runAiSubtasks(
  BuildContext context,
  Task task, {
  required VoidCallback onChanged,
}) async {
  if (!await _ensureAiReady(context)) return;
  if (!context.mounted) return;

  final hasExisting = task.subtasks.isNotEmpty;

  // 转圈框：不 await（它要等被 pop 才完成），跑完手动关掉
  showCupertinoDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => const CupertinoAlertDialog(
      content: Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(radius: 13),
            SizedBox(height: 14),
            Text('AI 正在拆解…', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    ),
  );

  List<AiStepDraft> steps = const <AiStepDraft>[];
  String? failure;
  try {
    steps = await AiTaskDraft.subtasksFor(task);
  } on AiException catch (error) {
    failure = error.message;
  } catch (error) {
    failure = '$error';
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // 关掉转圈框

  if (failure != null) {
    await _simple(context, '没能拆出来', failure);
    return;
  }
  if (steps.isEmpty) {
    await _simple(context, '没拆出来', 'AI 没给出可用的子待办。把待办的标题或描述写具体一点再试一次。');
    return;
  }

  final replace = await _preview(context, steps, hasExisting: hasExisting);
  if (replace == null) return; // 用户取消

  if (replace) task.subtasks.clear();
  for (final step in steps) {
    task.subtasks.add(step.toSubTask());
  }
  task.updatedAt = DateTime.now();
  onChanged();
}

Future<void> _simple(BuildContext context, String title, String message) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message, style: const TextStyle(fontSize: 14)),
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
}

/// 预览拆出来的子待办；返回 true = 替换现有，false = 追加，null = 取消
Future<bool?> _preview(
  BuildContext context,
  List<AiStepDraft> steps, {
  required bool hasExisting,
}) {
  bool? replace;
  return showCupertinoDialog<bool>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: const Text('AI 拆出了这些'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      step.timeLabel.isEmpty
                          ? '· ${step.title}'
                          : '· ${step.timeLabel}  ${step.title}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    if (step.location.isNotEmpty || step.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          [
                            if (step.location.isNotEmpty) step.location,
                            if (step.note.isNotEmpty) step.note,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('取消'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (hasExisting)
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('替换现有'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        CupertinoDialogAction(
          isDefaultAction: true,
          child: Text(hasExisting ? '追加' : '就用这些'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    ),
  );
}
