import 'package:celechron/model/task.dart';
import 'package:celechron/mod/system_alarm.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// 「把某条待办交给系统闹钟」的选择器。
///
/// 入口在「闹钟可靠性」弹窗里（手动、不常驻）。这里只做三件事：
/// 列出**适合交给系统时钟**的待办 → 让用户确认（并把限制说清楚）→ 提交给系统时钟。
Future<void> showSystemAlarmPicker(BuildContext context) async {
  final supported = await SystemAlarm.isSupported();
  if (!context.mounted) return;
  if (!supported) {
    await _info(context, '没有可用的系统时钟',
        '这台设备上没有能接收「设置闹钟」的应用，无法使用系统闹钟。');
    return;
  }

  final tasks = Get.find<RxList<Task>>(tag: 'taskList');
  final now = DateTime.now();
  final candidates = <MapEntry<Task, DateTime>>[];
  for (final task in tasks) {
    final at = systemAlarmTimeFor(task, now);
    if (at != null) candidates.add(MapEntry(task, at));
  }
  candidates.sort((a, b) => a.value.compareTo(b.value));

  final picked = await showCupertinoModalPopup<MapEntry<Task, DateTime>>(
    context: context,
    builder: (BuildContext context) => _SystemAlarmSheet(candidates: candidates),
  );
  if (picked == null || !context.mounted) return;

  final at = picked.value;
  // ⚠️ barrierDismissible: false 是必须的。
  // 选择器是在一次点击里 pop 掉的，紧接着弹出的对话框会在**同一次手指抬起**时
  // 收到事件；若允许点遮罩关闭，它会被自己立刻关掉 —— 实测就是这个现象
  // （弹层消失、确认框一闪即没）。这里强制用户明确选「取消」或「设成闹钟」。
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: const Text('交给系统闹钟？'),
      content: Text(
        '「${picked.key.summary}」\n'
        '${at.year}-${_two(at.month)}-${_two(at.day)} ${_two(at.hour)}:${_two(at.minute)}\n\n'
        '系统闹钟是**一次性**的，而且**不会随着待办完成或删除而撤销** —— '
        '以后要改时间或取消，得自己打开「时钟」应用操作。',
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('取消'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          child: const Text('设成闹钟'),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final ok = await SystemAlarm.set(
    at: at,
    label: systemAlarmLabelFor(picked.key),
  );
  if (!context.mounted) return;
  await _info(
    context,
    ok ? '已交给系统时钟' : '没能设成闹钟',
    ok
        ? '闹钟已写入「时钟」应用，到点会像起床闹钟一样响。\n'
            '要改时间或取消，请到「时钟」应用里操作（我们撤不掉它）。'
        : '系统拒绝了这次请求。可以打开「时钟」应用手动加一个闹钟。',
  );
}

String _two(int value) => value.toString().padLeft(2, '0');

Future<void> _info(BuildContext context, String title, String message) {
  return showCupertinoDialog<void>(
    context: context,
    // 同样不能让遮罩把结果提示吞掉：它往往紧跟一次点击弹出
    barrierDismissible: false,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message),
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

class _SystemAlarmSheet extends StatelessWidget {
  final List<MapEntry<Task, DateTime>> candidates;

  const _SystemAlarmSheet({required this.candidates});

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('交给系统闹钟',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '只列出还没到点、且设了提醒或时间的待办。'
                    '系统闹钟优先级等同起床闹钟，但**不会随待办撤销**。',
                    style: TextStyle(fontSize: 12.5, color: labelColor),
                  ),
                ],
              ),
            ),
            Flexible(
              child: candidates.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                      child: Text(
                        '现在没有适合交给系统闹钟的待办。\n'
                        '（备忘型不提醒；时间已经过去的不列出来）',
                        style: TextStyle(fontSize: 13, color: labelColor),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: candidates.length,
                      itemBuilder: (context, index) {
                        final entry = candidates[index];
                        final at = entry.value;
                        return CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.of(context).pop(entry),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 96,
                                  child: Text(
                                    '${at.month}月${at.day}日 '
                                    '${_two(at.hour)}:${_two(at.minute)}',
                                    style: TextStyle(
                                        fontSize: 13, color: labelColor),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    entry.key.summary.isEmpty
                                        ? '(无标题)'
                                        : entry.key.summary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                                const Icon(CupertinoIcons.chevron_forward,
                                    size: 14, color: CupertinoColors.systemGrey),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.systemFill, context),
                  borderRadius: BorderRadius.circular(22),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
