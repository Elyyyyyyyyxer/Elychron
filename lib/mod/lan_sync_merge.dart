import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/mod/focus_device.dart';
import 'package:celechron/mod/task_runtime_mod.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/utils/data_backup.dart';
import 'package:celechron/mod/lan_sync_conflict.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:celechron/utils/task_json.dart';
import 'package:get/get.dart';

/// ===== 把对方那台设备的数据合并进本机（局域网同步的公共部分）=====
///
/// 这段逻辑两个方向都要用：
/// - **当服务器时**：对方（客户端）把整份数据推过来 → 本机合并；
/// - **当客户端时**：从对方（服务器）拉来整份数据 → 本机合并。
///
/// 所以它必须只有一份实现 —— 两处各写一遍的话，合并口径迟早不一致，
/// 那才是同步事故的来源。
///
/// [localExportedAt] 是"本机上一次把数据交出去的时刻"（见 LanSyncServer.lastPullAt）：
/// 用来判断对方那份是不是比我们给出去的更新，设置项整组取舍要用它。
/// 从没交出去过（null）就按对方更新处理，也就是首次同步以对方为准。
Future<Map<String, dynamic>> mergeIncomingBundle({
  required DataBundle incoming,
  DateTime? localExportedAt,
}) async {
  final db = Get.find<DatabaseHelper>(tag: 'db');
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');

  // 合并前先落一份本地备份：万一合并出意外，用户的原始数据还在
  await DataBackup.writeLocalBackup(db, taskList);

  // 合并前先把本机这一版留个底：冲突要展示"本机值 vs 对方值"，得两版都在
  final localByUid = <String, Task>{
    for (final task in taskList) task.uid: task,
  };

  // 专注记录：本机删过的 + 对方删过的，合并时都算"已删除"，
  // 否则删掉的记录会被对方原样带回来（原来删除不参与同步）
  final deletedFocusUids = <String>{
    ...FocusDevice.deletedUids(),
    ...incoming.focusDeletedUids,
  };

  final result = DataMerge.merge(
    local: taskList.toList(),
    localTombstones: db.getTombstones(),
    incoming: incoming,
    localFocusSessions: db.getFocusSessions(),
    localDeletedFocusUids: deletedFocusUids,
    localExportedAt: localExportedAt,
  );

  // 收下对方的设备标注与删除记录（不动 Hive 结构，见 mod/focus_device.dart）
  await FocusDevice.adopt(incoming.focusSessionDevices);
  await FocusDevice.adoptDeleted(incoming.focusDeletedUids);
  await DataBackup.applyMerge(db, taskList, result, bundle: incoming);
  taskList.refresh();

  // ===== 字段级冲突：把"两边都改过"的待办逐字段记下来，等用户挑 =====
  //
  // 合并口径是整条按 updatedAt 晚者胜，晚的那条会把另一边的字段改动盖掉。
  // 这里把被盖掉的字段连同两边的原值一起存起来（LanSyncConflict），
  // 界面上让用户逐字段选；选完写回本机并抬高 updatedAt，下次同步就按他选的传播。
  if (result.conflictUids.isNotEmpty) {
    final remoteByUid = <String, Task>{
      for (final task in incoming.tasks) task.uid: task,
    };
    final detected = <LanSyncConflict>[];
    for (final uid in result.conflictUids) {
      final localTask = localByUid[uid];
      final remoteTask = remoteByUid[uid];
      if (localTask == null || remoteTask == null) continue;
      final diff = diffTasks(localTask, remoteTask);
      if (diff.isEmpty) continue;
      detected.add(LanSyncConflict(
        uid: uid,
        title: remoteTask.summary.trim().isEmpty
            ? localTask.summary.trim()
            : remoteTask.summary.trim(),
        fields: diff,
        detectedAt: DateTime.now(),
        localJson: TaskJson.taskToJson(localTask),
        remoteJson: TaskJson.taskToJson(remoteTask),
      ));
    }
    if (detected.isNotEmpty) {
      final existing = LanSyncConflictStore.load()
        ..removeWhere((item) => detected.any((d) => d.uid == item.uid));
      await LanSyncConflictStore.save(
          <LanSyncConflict>[...existing, ...detected]);
    }
  }

  // 合并后的任务必须立即重算状态并重排提醒；不能因为待办页尚未打开就跳过，
  // 否则远端新建的提醒只会存进去，不会真正调度。
  if (Get.isRegistered<TaskController>()) {
    final controller = Get.find<TaskController>();
    controller.updateDeadlineList();
    controller.updateDeadlineListTime();
  } else {
    syncTaskReminders(taskList);
  }

  return <String, dynamic>{
    'ok': true,
    'summary': result.summary,
    'device': incoming.deviceId,
    'conflicts': result.conflictUids.length,
  };
}
