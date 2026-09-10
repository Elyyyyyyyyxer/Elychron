import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:path_provider/path_provider.dart';

/// 导出 / 导入（同时是后续多端同步的基础）：
/// 把整份数据序列化成 JSON 文件，或从 JSON 文件合并回来。
class DataBackup {
  DataBackup._();

  static const String filePrefix = 'celechron-backup';

  /// 收集当前全部数据
  static DataBundle currentBundle(
    DatabaseHelper db,
    List<Task> tasks,
  ) {
    return DataBundle(
      exportedAt: DateTime.now(),
      tasks: List<Task>.of(tasks),
      tombstones: db.getTombstones(),
      tags: db.getTagLibrary(),
      tagColors: db.getTagColors(),
      reminderMode: db.getReminderMode(),
      alarmTheme: db.getAlarmTheme(),
    );
  }

  static String fileName([DateTime? at]) {
    final time = at ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '$filePrefix-${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}.json';
  }

  /// 导出到应用文档目录，返回文件（用于分享 / 上传坚果云）
  static Future<File> writeExportFile(
    DatabaseHelper db,
    List<Task> tasks,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/celechron_backup');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final file = File('${exportDir.path}/${fileName()}');
    await file.writeAsString(currentBundle(db, tasks).encode());
    return file;
  }

  /// 导入前的本地兜底备份（合并逻辑万一有问题还能救回来）
  static Future<File?> writeLocalBackup(
    DatabaseHelper db,
    List<Task> tasks,
  ) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/celechron_backup');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final file = File('${backupDir.path}/before-import.json');
      await file.writeAsString(currentBundle(db, tasks).encode());
      return file;
    } catch (_) {
      return null;
    }
  }

  /// 把合并结果写回数据库
  static Future<void> applyMerge(
    DatabaseHelper db,
    List<Task> taskList,
    MergeResult result, {
    DataBundle? bundle,
  }) async {
    taskList
      ..clear()
      ..addAll(result.tasks);
    await db.setTaskList(taskList);
    await db.setTombstones(result.tombstones);

    if (bundle != null) {
      // 标签库：合并（保留本地顺序，追加远端新增的）
      final tags = db.getTagLibrary();
      for (final tag in bundle.tags) {
        if (!tags.contains(tag)) tags.add(tag);
      }
      if (tags.isNotEmpty) {
        await db.setTagLibrary(tags, allowEmpty: true);
      }
      final colors = db.getTagColors();
      bundle.tagColors.forEach((key, value) {
        colors.putIfAbsent(key, () => value);
      });
      await db.setTagColors(colors);
    }
  }
}
