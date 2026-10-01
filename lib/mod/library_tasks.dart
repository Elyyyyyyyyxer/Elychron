import 'dart:convert';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/library_spider.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/mod/data_change.dart';
import 'package:celechron/mod/library_config.dart';
import 'package:celechron/mod/library_web_session.dart';
import 'package:get/get.dart';

/// ===== 图书馆预约自动进待办（2026-10-01）=====
///
/// 和 homework_tasks.dart 同一套写法（那是"作业自动进待办"的样板），三点一致：
/// 1. **稳定 uid**：lib-<预约 id> —— 反复同步只更新那一条，不会长出一堆重复待办；
/// 2. **只增不删**：读不到/登录被顶掉/网络不好，都绝不动用户已有的待办；
/// 3. 打完收工：setTaskList → sort → refresh → notifyDataChanged（跨设备同步也跟着走）。
///
/// 和作业那套唯一的区别：预约是**时段**，所以要 startTime + endTime 都填，
/// 到点提醒才说得清"什么时候该去、什么时候结束"。
const String kLibraryTag = '图书馆';
const String kLibraryUidPrefix = 'lib-';

/// 这条预约要不要变成待办（纯函数，单测钉着）
bool libraryReservationWanted(LibraryReservation reservation) =>
    reservation.id.isNotEmpty &&
    reservation.start != null &&
    reservation.end != null &&
    !reservation.status.contains('取消');

/// 待办标题：地点在场就带上（"团队讨论 · 主馆-二层-207"）
String libraryTaskSummary(LibraryReservation reservation) =>
    reservation.place.isEmpty
        ? reservation.title
        : reservation.title + ' · ' + reservation.place;

/// 图书馆的预约排前面，其次按开始时间
int libraryFirst(Task a, Task b) {
  final rank = (a.tags.contains(kLibraryTag) ? 0 : 1)
      .compareTo(b.tags.contains(kLibraryTag) ? 0 : 1);
  if (rank != 0) return rank;
  final left = a.startTime ?? a.endTime;
  final right = b.startTime ?? b.endTime;
  if (left == null || right == null) return 0;
  return left.compareTo(right);
}

/// 把"我的预约"同步成待办。返回一句人话，供界面显示。
Future<String> syncLibraryReservations({
  required DatabaseHelper db,
  required RxList<Task> taskList,
  DateTime? now,
}) async {
  final session = LibraryWebSession.instance;
  if (!session.available) return '桌面端暂时没有内置浏览器，无法同步预约';

  // 三个来源各读一次；单个失败不影响其它（活动接口偶发 500）
  final byId = <String, LibraryReservation>{};
  for (final path in const <String>[
    '/api/Member/seat',
    '/api/Member/room',
    '/api/Member/seminar',
  ]) {
    try {
      final body = await session.postJson(path);
      for (final reservation
          in LibrarySpider.reservationsFrom(jsonDecode(body))) {
        if (reservation.id.isEmpty) continue;
        byId[reservation.id] = reservation;
      }
    } on LibraryAuthException {
      // 登录被顶掉：如实说，但**不清空**已有待办
      await LibraryConfig.setLastResult('同步失败：登录可能被其它设备顶掉了');
      return '同步失败：' + '登录可能被其它设备顶掉了';
    } on Object catch (error) {
      libraryTrace('同步预约：' + path + ' 失败：' + error.toString());
    }
  }

  // 一条都没读到 → 什么都不做（绝不动已有待办）
  if (byId.isEmpty) return '没读到预约（本次不改动任何待办）';

  final at = now ?? DateTime.now();
  var added = 0;
  var updated = 0;

  for (final reservation in byId.values) {
    if (!libraryReservationWanted(reservation)) continue;
    final start = reservation.start!;
    final end = reservation.end!;
    final uid = kLibraryUidPrefix + reservation.id;
    final summary = libraryTaskSummary(reservation);

    final index = taskList.indexWhere((task) => task.uid == uid);
    if (index < 0) {
      final task = Task(
        summary: summary,
        startTime: start,
        endTime: end,
        repeatEndsTime: end,
      );
      task.uid = uid;
      task.priority = TaskPriority.high;
      task.tags = <String>[kLibraryTag];
      task.description = '来自图书馆预约' +
          (reservation.status.isEmpty ? '' : '（' + reservation.status + '）');
      taskList.add(task);
      added++;
      continue;
    }

    // 已有 → 只更新会变的那几项，**不碰**用户自己加的子待办/备注
    final existing = taskList[index];
    var touched = false;
    if (existing.summary != summary) {
      existing.summary = summary;
      touched = true;
    }
    if (existing.startTime == null || !existing.startTime!.isAtSameMomentAs(start)) {
      existing.startTime = start;
      touched = true;
    }
    if (existing.endTime == null || !existing.endTime!.isAtSameMomentAs(end)) {
      existing.endTime = end;
      existing.repeatEndsTime = end;
      touched = true;
    }
    if (!existing.tags.contains(kLibraryTag)) {
      existing.tags = <String>[...existing.tags, kLibraryTag];
      touched = true;
    }
    if (touched) {
      existing.updatedAt = at;
      updated++;
    }
  }

  final wanted = byId.values.where(libraryReservationWanted).length;
  if (added == 0 && updated == 0) {
    return '预约已是最新（' + wanted.toString() + ' 条）';
  }

  await db.setTaskList(taskList);
  taskList
    ..sort(libraryFirst)
    ..refresh();
  // 待办也是用户数据，同步推一次（用户要求"每次操作都同步"）
  notifyDataChanged();

  var result = '已同步 ' + wanted.toString() + ' 条预约';
  if (added > 0) result = result + '，新增 ' + added.toString();
  if (updated > 0) result = result + '，更新 ' + updated.toString();
  return result;
}
