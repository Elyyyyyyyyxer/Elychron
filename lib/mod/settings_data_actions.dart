import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/mod/feedback_copy.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/utils/data_backup.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:celechron/utils/time_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

/// ============ 设置页里「数据（导出 / 导入）」的实现 ============
///
/// 上游的 `lib/page/option/option_view.dart` 一直在更新（1.3 就加了 36 行），
/// 所以这段实现放在这里，那个文件里只留两个调用点（见 `// ===== MOD =====`）。
Future<void> modExportData(BuildContext context) async {
  final db = Get.find<DatabaseHelper>(tag: 'db');
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');
  final box = context.findRenderObject() as RenderBox?;
  try {
    final file = await DataBackup.writeExportFile(db, taskList);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: 'Elychron 备份',
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  } catch (e) {
    if (context.mounted) {
      modAlert(context, '导出失败', '$e');
    }
  }
}

Future<void> modImportData(BuildContext context) async {
  final db = Get.find<DatabaseHelper>(tag: 'db');
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');

  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  final path = picked?.files.firstOrNull?.path;
  if (path == null) return;

  DataBundle? bundle;
  try {
    bundle = DataBundle.decode(await File(path).readAsString());
  } catch (_) {
    bundle = null;
  }
  if (bundle == null) {
    if (context.mounted) {
      modAlert(context, '无法导入', '这个文件不是 Elychron 导出的备份，或者内容已损坏。');
    }
    return;
  }

  // 先在内存里试算合并结果，让用户看到会变成什么样
  final merged = DataMerge.merge(
    local: taskList.toList(),
    localTombstones: db.getTombstones(),
    incoming: bundle,
    // 文件导入是用户显式的「恢复」动作，专注记录也要跟着合，
    // 并且设置以文件里的为准（不传 localExportedAt）
    localFocusSessions: db.getFocusSessions(),
  );

  if (!context.mounted) return;
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: const Text('导入备份'),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '备份导出时间：${TimeHelper.chineseDateTime(bundle!.exportedAt)}\n'
          '包含 ${bundle.tasks.length} 条待办、${bundle.tags.length} 个标签\n\n'
          '${merged.summary}\n\n'
          '导入前会自动在本地留一份备份。',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('取消'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          child: const Text('导入'),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  await DataBackup.writeLocalBackup(db, taskList);
  await DataBackup.applyMerge(db, taskList, merged, bundle: bundle);
  final controller = Get.find<TaskController>();
  controller.updateDeadlineList();
  controller.taskList.refresh();

  if (context.mounted) {
    modAlert(context, '导入完成', merged.summary);
  }
}

/// 一键复制「反馈信息」：机型 / 系统 / 版本 + 脱敏日志 + 反馈模板。
///
/// 目的是把反馈门槛压到最低 —— 用户粘一段文字就能在 QQ 群 / 论坛帖里说清楚，
/// 我们也不用再追问"你什么机型、什么版本、日志呢"。
Future<void> modCopyFeedback(BuildContext context) async {
  try {
    final text = await FeedbackCopy.build();
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      modAlert(
        context,
        '已复制反馈信息',
        '机型、系统版本、App 版本与最近 ${FeedbackCopy.logTailLines} 行'
        '**已脱敏**日志都在剪贴板里了。\n\n'
        '把它粘到反馈渠道（QQ 群 / 论坛帖 / Gitee Issue），'
        '再补上复现步骤即可。\n\n'
        '日志里的密码、Cookie、学号已自动隐藏。',
      );
    }
  } catch (e) {
    if (context.mounted) {
      modAlert(context, '复制失败', '$e');
    }
  }
}

void modAlert(BuildContext context, String title, String message) {
  showCupertinoDialog<void>(
    context: context,
    builder: (BuildContext context) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message, style: const TextStyle(fontSize: 14)),
      ),
      actions: [
        CupertinoDialogAction(
          child: const Text('好'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}
