import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/mod/task_runtime_mod.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/utils/data_backup.dart';
import 'package:celechron/utils/data_sync.dart';
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

  final result = DataMerge.merge(
    local: taskList.toList(),
    localTombstones: db.getTombstones(),
    incoming: incoming,
    localFocusSessions: db.getFocusSessions(),
    localExportedAt: localExportedAt,
  );
  await DataBackup.applyMerge(db, taskList, result, bundle: incoming);
  taskList.refresh();

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
