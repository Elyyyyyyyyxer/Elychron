import 'dart:convert';
import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/mod/feedback_copy.dart';
import 'package:celechron/mod/friendly_error.dart';
import 'package:celechron/mod/ical_import.dart';
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
import 'package:celechron/mod/friendly_error.dart';

/// ============ 设置页里数据（导出 / 导入）的实现 ============
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
      // 只说人话；细节在设置 → 诊断与测试里能看
      modAlert(
          context, '导出失败', FriendlyError.short(e, fallback: '导出没成功，请稍后重试'));
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
    // 文件导入是用户显式的恢复动作，专注记录也要跟着合，
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

/// 导入 iCal（.ics）文件：解析出每条日程，转成待办。
///
/// 按用户要求**只进 Elychron 的待办**，不写系统日历。
/// 去重靠 iCal 自带的 UID：同一个文件重复导入不会产生重复待办。
Future<void> modImportIcal(BuildContext context) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      // 为什么用 any 而不是按扩展名过滤：
      // Android 上 `allowedExtensions: ['ics']` 会被映射成 MIME 过滤（text/calendar），
      // 而很多 .ics（浏览器直下、聊天软件转发、adb 推的）**没有登记 MIME**，
      // 于是文件明明在那儿、选择器里却看不到， 实测就是这么翻车的。
      // 所以放开选择，读出来之后再校验内容（下面会检查有没有 VEVENT）。
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (context.mounted) modAlert(context, '读取失败', '拿不到文件内容，请换一个文件试试。');
      return;
    }
    var text = utf8.decode(bytes, allowMalformed: true);
    // 去掉 UTF-8 BOM（有些日历导出的文件带）
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    final events = IcalImporter.parseIcal(text);
    if (events.isEmpty) {
      if (context.mounted) {
        modAlert(context, '没找到日程', '这个文件里没有可识别的日程（VEVENT）。');
      }
      return;
    }

    final taskList = Get.find<RxList<Task>>(tag: 'taskList');
    final existing = taskList.map((task) => task.uid).toSet();
    final plan = IcalImporter.plan(events, existingUids: existing);

    if (!context.mounted) return;
    if (plan.isEmpty) {
      modAlert(context, '都导入过了', '${plan.summary}。');
      return;
    }

    // 确认：列前几条标题，让用户知道要进来什么
    final preview =
        plan.tasks.take(5).map((task) => '· ${task.summary}').join('\n');
    final more =
        plan.tasks.length > 5 ? '\n…… 还有 ${plan.tasks.length - 5} 条' : '';
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('导入 iCal 日程'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(plan.summary, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Text('$preview$more', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              const Text(
                '有起止的会导入成活动，只有一个时刻的按提醒或截止，'
                '都没有的按备忘。重复导入同一个文件不会产生重复待办。',
                style: TextStyle(fontSize: 12),
              ),
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
            child: const Text('导入'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    taskList.addAll(plan.tasks);
    final controller = Get.find<TaskController>();
    controller.updateDeadlineList();
    controller.updateDeadlineListTime();
    controller.taskList.refresh();

    if (context.mounted) {
      modAlert(
        context,
        '导入完成',
        '新增 ${plan.tasks.length} 条待办'
            '${plan.skipped.isEmpty ? '' : '，跳过 ${plan.skipped.length} 条已存在的'}。',
      );
    }
  } catch (e) {
    if (context.mounted) {
      modAlert(context, '导入失败',
          FriendlyError.short(e, fallback: '这个 iCal 文件读不出来，请确认格式'));
    }
  }
}

/// 一键复制反馈信息：机型 / 系统 / 版本 + 脱敏日志 + 反馈模板。
///
/// 目的是把反馈门槛压到最低， 用户粘一段文字就能在 QQ 群 / 论坛帖里说清楚，
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
            '已脱敏日志已保存进剪贴板。\n\n'
            '请粘贴到反馈渠道（QQ 群 / 论坛帖 / Gitee Issue），'
            '再补上复现步骤即可。\n\n'
            '日志里的密码、Cookie、学号已自动隐藏。',
      );
    }
  } catch (e) {
    if (context.mounted) {
      modAlert(
          context, '复制失败', FriendlyError.short(e, fallback: '复制没成功，请稍后重试'));
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
