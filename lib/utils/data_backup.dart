import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:path_provider/path_provider.dart';

/// 导出 / 导入（同时是后续多端同步的基础）：
/// 把整份数据序列化成 JSON 文件，或从 JSON 文件合并回来。
class DataBackup {
  DataBackup._();

  static const String filePrefix = 'celechron-backup';

  /// 收集当前全部数据
  ///
  /// 同步范围见 [DataBundle] 的文档注释：用户自己产生的数据全都要，
  /// 从学校服务器拉的（课表/成绩/校园卡）**不要**，教务网密码**永远不要**。
  /// [includeSecrets] 为 false 时不带密钥（用户可以在同步设置里关掉）。
  static Future<DataBundle> currentBundle(
    DatabaseHelper db,
    List<Task> tasks, {
    bool includeSecrets = true,
  }) async {
    return DataBundle(
      exportedAt: DateTime.now(),
      deviceId: db.getDeviceId(),
      tasks: List<Task>.of(tasks),
      tombstones: db.getTombstones(),
      tags: db.getTagLibrary(),
      tagColors: db.getTagColors(),
      reminderMode: db.getReminderMode(),
      alarmTheme: db.getAlarmTheme(),
      focusSessions: db.getFocusSessions(),
      focusWorkMinutes: db.getFocusWorkMinutes(),
      focusRestMinutes: db.getFocusRestMinutes(),
      focusRestNotify: db.getFocusRestNotify(),
      reminderLeadMinutes: db.getReminderLeadMinutes(),
      brightnessMode: db.getBrightnessMode().index,
      courseIdMapping:
          db.getCourseIdMappingList().map((item) => item.toJson()).toList(),
      secrets: includeSecrets
          ? await db.getSyncSecrets()
          : const <String, String>{},
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
    await file.writeAsString((await currentBundle(db, tasks)).encode());
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
      await file.writeAsString((await currentBundle(db, tasks)).encode());
      return file;
    } catch (_) {
      return null;
    }
  }

  /// 把合并结果写回数据库
  ///
  /// S1 扩展：除了待办与标签，还会写回**专注记录**、以及（当对方那份更新时）
  /// **设置项与白名单内的密钥**。
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

    // 专注记录（合并结果里已经是「按 uid 去重 + 本端在跑优先」之后的）
    if (result.focusSessions.isNotEmpty) {
      for (final session in result.focusSessions) {
        await db.saveFocusSession(session);
      }
    }

    if (bundle == null) return;

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

    // 设置项：整组按「谁导出的更晚」取舍（见 DataMerge.merge）
    if (result.settingsTakenFromRemote) {
      db.setReminderMode(bundle.reminderMode);
      db.setAlarmTheme(bundle.alarmTheme);
      db.setFocusWorkMinutes(bundle.focusWorkMinutes);
      db.setFocusRestMinutes(bundle.focusRestMinutes);
      db.setFocusRestNotify(bundle.focusRestNotify);
      db.setReminderLeadMinutes(bundle.reminderLeadMinutes);
      if (bundle.brightnessMode >= 0 &&
          bundle.brightnessMode < BrightnessMode.values.length) {
        db.setBrightnessMode(BrightnessMode.values[bundle.brightnessMode]);
      }
      if (bundle.courseIdMapping.isNotEmpty) {
        await db.setCourseIdMappingList(bundle.courseIdMapping
            .map((json) => CourseIdMap.fromJson(json))
            .toList());
      }
      // 密钥：只在用户允许同步时（对方的包里带了）才写
      if (bundle.secrets.isNotEmpty) {
        await db.applySyncSecrets(bundle.secrets);
      }
    }
  }
}
