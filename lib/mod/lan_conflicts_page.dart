import 'package:celechron/design/page_background.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/lan_sync_conflict.dart';
import 'package:celechron/mod/task_runtime_mod.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/task_json.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ===== 处理同步冲突（v1.5.0）=====
///
/// 用户要求：「两边都改过的时候展示冲突的字段，允许在其中做选择」。
///
/// 合并口径是**整条按 updatedAt 晚者胜**，所以晚改的那条会把另一边的字段改动盖掉。
/// 这个页面把被盖掉的字段一条条列出来，每一行给出「本机 / 对方」两个值，
/// 点哪个就用哪个；选完写回本机并抬高 updatedAt，下一次同步按你选的传播。
class LanConflictsPage extends StatefulWidget {
  const LanConflictsPage({super.key});

  @override
  State<LanConflictsPage> createState() => _LanConflictsPageState();
}

class _LanConflictsPageState extends State<LanConflictsPage> {
  List<LanSyncConflict> _conflicts = <LanSyncConflict>[];

  static const Color _accent = Color(0xFFFF699A);

  @override
  void initState() {
    super.initState();
    _conflicts = LanSyncConflictStore.load();
  }

  DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  RxList<Task>? get _taskList {
    try {
      return Get.find<RxList<Task>>(tag: 'taskList');
    } catch (_) {
      return null;
    }
  }

  /// 用某一侧的取值覆盖本机这条待办的某一个字段
  ///
  /// 只动**这一个字段**：其余字段保持合并后的样子，避免"选一个字段把整条都换掉"。
  Future<void> _apply(
    LanSyncConflict conflict,
    String label, {
    required bool takeRemote,
  }) async {
    final list = _taskList;
    final db = _db;
    if (list == null || db == null) return;
    final json = takeRemote ? conflict.remoteJson : conflict.localJson;
    final source = TaskJson.taskFromJson(json);
    final index = list.indexWhere((task) => task.uid == conflict.uid);
    if (source == null || index < 0) {
      // 这条待办已经不在了（被删了之类）→ 直接把冲突划掉
      await _dropConflict(conflict);
      return;
    }
    final target = list[index];
    _copyField(target, source, label);
    // 抬高更新时间：下一次同步就以这次选择为准
    target.updatedAt = DateTime.now();
    await db.setTaskList(list);
    list.refresh();
    syncTaskReminders(list);

    // 这个字段处理完了，从冲突里移除；一个字段都不剩就把整条冲突去掉
    final remaining = Map<String, List<String>>.of(conflict.fields)
      ..remove(label);
    final next = _conflicts
        .where((item) => item.uid != conflict.uid)
        .toList(growable: true);
    if (remaining.isNotEmpty) {
      next.add(LanSyncConflict(
        uid: conflict.uid,
        title: conflict.title,
        fields: remaining,
        detectedAt: conflict.detectedAt,
        localJson: conflict.localJson,
        remoteJson: conflict.remoteJson,
      ));
    }
    await LanSyncConflictStore.save(next);
    if (mounted) setState(() => _conflicts = next);
  }

  /// 某一条冲突整体用本机 / 整体用对方
  Future<void> _applyAll(LanSyncConflict conflict,
      {required bool takeRemote}) async {
    for (final label in conflict.fields.keys.toList()) {
      await _apply(conflict, label, takeRemote: takeRemote);
    }
  }

  Future<void> _dropConflict(LanSyncConflict conflict) async {
    final next = _conflicts.where((item) => item.uid != conflict.uid).toList();
    await LanSyncConflictStore.save(next);
    if (mounted) setState(() => _conflicts = next);
  }

  /// 字段名 → 抄哪个属性
  ///
  /// 字段名与 diffTasks 里那套一一对应（那边是唯一来源，这里是落地动作）。
  static void _copyField(Task target, Task source, String label) {
    switch (label) {
      case '标题':
        target.summary = source.summary;
      case '描述':
        target.description = source.description;
      case '类型':
        target.type = source.type;
      case '地点':
        target.location = source.location;
      case '开始时间':
        target.startTime = source.startTime;
      case '截止时间':
        target.endTime = source.endTime;
      case '标签':
        target.tags = List<String>.of(source.tags);
      case '星标':
        target.starred = source.starred;
      case '优先级':
        target.priority = source.priority;
      case '子待办':
        target.subtasks = List<SubTask>.of(source.subtasks);
      case '附件':
        target.attachments = List<TaskAttachment>.of(source.attachments);
      case '评论':
        target.comments = List<TaskComment>.of(source.comments);
      case '提醒':
        target.reminderEnabled = source.reminderEnabled;
      case '提醒时间':
        target.reminderTime = source.reminderTime;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return CupertinoPageScaffold(
      backgroundColor: pageBackground(context),
      navigationBar: const CupertinoNavigationBar(middle: Text('处理冲突')),
      child: SafeArea(
        child: _conflicts.isEmpty
            ? Center(
                child: Text('没有待处理的冲突',
                    style: TextStyle(fontSize: 14, color: labelColor)),
              )
            : ListView(
                padding: EdgeInsets.only(
                  top: 12,
                  bottom: 24 + MediaQuery.of(context).padding.bottom,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 4, 26, 14),
                    child: Text(
                      '下面这些待办两台设备都改过。逐条选一下要保留哪一边 —— '
                      '只影响你选的那个字段，其余字段保持合并后的结果。',
                      style: TextStyle(fontSize: 13, color: labelColor),
                    ),
                  ),
                  for (final conflict in _conflicts)
                    _conflictCard(context, conflict, labelColor),
                ],
              ),
      ),
    );
  }

  Widget _conflictCard(
      BuildContext context, LanSyncConflict conflict, Color labelColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: RoundRectangleCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    conflict.title.isEmpty ? '（未命名待办）' : conflict.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  onPressed: () => _applyAll(conflict, takeRemote: false),
                  child: const Text('全用本机', style: TextStyle(fontSize: 12.5)),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  onPressed: () => _applyAll(conflict, takeRemote: true),
                  child: const Text('全用对方', style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final entry in conflict.fields.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(entry.key,
                    style: TextStyle(fontSize: 12.5, color: labelColor)),
              ),
              _choiceRow(
                label: '本机',
                value: entry.value.isNotEmpty ? entry.value[0] : '',
                onTap: () => _apply(conflict, entry.key, takeRemote: false),
              ),
              const SizedBox(height: 6),
              _choiceRow(
                label: '对方',
                value: entry.value.length > 1 ? entry.value[1] : '',
                onTap: () => _apply(conflict, entry.key, takeRemote: true),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 一个可点的取值行：点它 = 用这个值
  Widget _choiceRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill.resolveFrom(Get.context!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: _accent)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value.isEmpty ? '（空）' : value,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
