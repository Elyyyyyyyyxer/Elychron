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
/// 和作业那套唯一的区别：预约是**时段**，所以 startTime + endTime 都填，
/// 到点提醒才说得清"什么时候该去、什么时候结束"。
const String kLibraryTag = '图书馆';
const String kLibraryUidPrefix = 'lib-';

/// 待办标题的长度上限（纯函数钉着，免得真机上又出现一条占满屏幕的标题）。
const int kLibraryTaskTitleMax = 24;

/// 三类预约的标题前缀（用户拍板的固定格式）。
const String kLibrarySeatLabel = '图书馆座位';
const String kLibraryRoomLabel = '图书馆研讨间';
const String kLibraryActivityLabel = '图书馆活动';

/// 待办描述固定以它开头 —— 判断"这条描述还是我们生成的那份"用，
/// 用户自己改过就绝不再覆盖（见 syncLibraryReservations 的更新分支）。
const String kLibraryDescriptionPrefix = '图书馆预约';

/// 第一版（2026-10-01 早些时候）生成的描述前缀："来自图书馆预约（8）"。
/// 留一个常量专门用来识别并升级它们，否则那些待办的长标题永远进不了描述。
const String kLegacyDescriptionPrefix = '来自图书馆预约';

/// 这条预约现在**还生效**吗（纯函数，单测钉着）。
///
/// 只认两件事：结束时间还在将来、状态不是「已取消 / 已使用」。
///
/// 为什么必须这么判：用户明确说过"已完成的预约不能变成未完成的逾期待办"。
/// 过去每同步一次都会给历史预约建一条待办，界面上显示成"已过期"，就是漏了这道判据。
bool libraryReservationActive(LibraryReservation reservation, {DateTime? now}) {
  final end = reservation.end;
  if (end == null) return false;
  final at = now ?? DateTime.now();
  if (!end.isAfter(at)) return false;
  final status = reservation.status.trim();
  if (status.contains('取消')) return false;
  if (status.contains('已使用')) return false;
  return true;
}

/// 这条预约要不要变成待办（纯函数，单测钉着）
bool libraryReservationWanted(LibraryReservation reservation, {DateTime? now}) =>
    reservation.id.isNotEmpty &&
    reservation.start != null &&
    reservation.end != null &&
    libraryReservationActive(reservation, now: now);

/// 这条预约属于哪一类（决定待办标题前缀）。
///
/// **按数据判，不按接口名判**：真机上 /api/Member/seminar 返回的其实是研讨间
/// （nameMerge 是"主馆-二层-207(8人间)"），而接口名里带 seminar 的东西
/// 也可能真的是活动。所以先看条目自己的字段，再看地点/标题里有没有房间线索。
String libraryReservationKind(LibraryReservation reservation) {
  final seat = reservation.seatNo.trim();
  if (reservation.kind == 'seat' || seat.isNotEmpty) return 'seat';
  if (reservation.roomName.trim().isNotEmpty) return 'room';
  if (reservation.kind == 'room') return 'room';
  final haystack = reservation.place + reservation.title;
  if (RegExp('研讨|人间|会议室').hasMatch(haystack)) return 'room';
  return 'activity';
}

/// 从长标题里抠出短标题：去掉括号里的说明。
///
/// 用户原话："这个空间的预约就一长串，根本没有重点"。真机上的长标题长这样：
/// "团队讨论(班团,社团,兴趣小组,项目讨论)" —— 有用的是前面四个字。
String libraryShortTitle(String raw) {
  final text = raw.trim();
  var index = -1;
  for (final bracket in const <String>['(', '（']) {
    final at = text.indexOf(bracket);
    if (at > 0 && (index < 0 || at < index)) index = at;
  }
  final short = index > 0 ? text.substring(0, index).trim() : text;
  return short.isEmpty ? text : short;
}

/// 只截断、不拼接：先补省略号再截，保证结果长度不超过 [maxLength]。
String _libraryClip(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  if (maxLength <= 1) return text.substring(0, maxLength);
  return text.substring(0, maxLength - 1) + '…';
}

String _libraryTitleBody(LibraryReservation reservation, String kind) {
  final place = reservation.place.trim();
  final seat = reservation.seatNo.trim();
  final room = reservation.roomName.trim();
  if (kind == 'seat') {
    if (seat.isNotEmpty) return seat;
    if (place.isNotEmpty) return place;
    return libraryShortTitle(reservation.title);
  }
  if (kind == 'room') {
    if (room.isNotEmpty) return room;
    if (place.isNotEmpty) return place;
    return libraryShortTitle(reservation.title);
  }
  final short = libraryShortTitle(reservation.title);
  if (short.isNotEmpty) return short;
  return place;
}

/// 待办标题：按类型取短标题（用户拍板的固定格式）。
///
///   座位类 → 图书馆座位 · <座位号 / 地点摘要>
///   研讨间 → 图书馆研讨间 · <房间摘要>
///   活动类 → 图书馆活动 · <短标题>
///
/// 原来的长标题不再占标题，改放 description（见 [libraryTaskDescription]）。
String libraryTaskTitle(LibraryReservation reservation,
    {int maxLength = kLibraryTaskTitleMax}) {
  final kind = libraryReservationKind(reservation);
  final label = switch (kind) {
    'seat' => kLibrarySeatLabel,
    'room' => kLibraryRoomLabel,
    _ => kLibraryActivityLabel,
  };
  final body = _libraryTitleBody(reservation, kind);
  final title = body.isEmpty ? label : label + ' · ' + body;
  return _libraryClip(title, maxLength);
}

/// 设置页列表里显示的一行：**地点 + 座位号 / 房间名**。
///
/// 用户反馈"看不到是哪个座位/哪个房间"，所以这里把两样都摆出来，
/// 重复时只留一份（真机上座位标题本身就带馆层）。
String libraryPlaceDetail(LibraryReservation reservation) {
  final parts = <String>[];
  final place = reservation.place.trim();
  if (place.isNotEmpty) parts.add(place);
  final detail = reservation.seatNo.trim().isNotEmpty
      ? reservation.seatNo.trim()
      : reservation.roomName.trim();
  if (detail.isNotEmpty && !place.contains(detail)) parts.add(detail);
  if (parts.isEmpty) {
    final short = libraryShortTitle(reservation.title);
    if (short.isNotEmpty) parts.add(short);
  }
  return parts.join(' · ');
}

String _libraryStamp(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return local.year.toString() +
      '-' +
      two(local.month) +
      '-' +
      two(local.day) +
      ' ' +
      two(local.hour) +
      ':' +
      two(local.minute);
}

/// 待办的 description：把原来的长标题、地点座位、状态、时间都写全
/// （标题已经很短了，详细信息得有个去处）。
///
/// 第一行必须是**有用的一句话**：待办卡片只显示描述的第一行（真机上看出来的），
/// 只写一个标记的话卡片上就只剩"图书馆预约"四个字，比原来的"来自图书馆预约（8）"还糟。
/// 同时这一行仍以 [kLibraryDescriptionPrefix] 开头，更新时才能认出"还是我们生成的那份"。
String libraryTaskDescription(LibraryReservation reservation) {
  final lines = <String>[];
  final detail = libraryPlaceDetail(reservation);
  final title = reservation.title.trim();
  final first = detail.isNotEmpty ? detail : title;
  if (first.isNotEmpty) {
    lines.add(kLibraryDescriptionPrefix + '：' + first);
  } else {
    lines.add(kLibraryDescriptionPrefix);
  }
  if (title.isNotEmpty && title != first && !first.contains(title)) {
    lines.add('预约内容：' + title);
  }
  final status = libraryStatusLabel(reservation);
  if (status.isNotEmpty) lines.add('状态：' + status);
  final start = reservation.start;
  final end = reservation.end;
  if (start != null && end != null) {
    lines.add('时间：' + _libraryStamp(start) + ' → ' + _libraryStamp(end));
  }
  return lines.join('\n');
}

/// 状态里该显示的那一段。
///
/// 座位接口给的是**编号**（实测是 "8"），直接显示出来就是界面上一个莫名其妙的"8"；
/// 只有像"已使用"/"已预约"这种真正的名字才显示。
String libraryStatusLabel(LibraryReservation reservation) {
  final status = reservation.status.trim();
  if (status.isEmpty) return '';
  if (RegExp(r'^[0-9]+$').hasMatch(status)) return '';
  return status;
}

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
  for (final source in const <({String path, String kind})>[
    (path: '/api/Member/seat', kind: 'seat'),
    (path: '/api/Member/room', kind: 'room'),
    (path: '/api/Member/seminar', kind: 'seminar'),
  ]) {
    try {
      final body = await session.postJson(source.path);
      LibrarySpider.traceResponse(source.path, body);
      for (final reservation in LibrarySpider.reservationsFrom(jsonDecode(body),
          kind: source.kind)) {
        if (reservation.id.isEmpty) continue;
        byId[reservation.id] = reservation;
      }
    } on LibraryAuthException catch (error) {
      // 登录被顶掉：如实说，但**不清空**已有待办
      libraryTrace('同步预约：' + source.path + ' 未登录：' + error.message);
      return '同步失败：' + error.message;
    } on Object catch (error) {
      libraryTrace('同步预约：' + source.path + ' 失败：' + error.toString());
    }
  }

  // 一条都没读到 → 什么都不做（绝不动已有待办）
  if (byId.isEmpty) return '没读到预约（本次不改动任何待办）';

  final at = now ?? DateTime.now();
  var added = 0;
  var updated = 0;

  for (final reservation in byId.values) {
    if (!libraryReservationWanted(reservation, now: at)) continue;
    final start = reservation.start!;
    final end = reservation.end!;
    final uid = kLibraryUidPrefix + reservation.id;
    final summary = libraryTaskTitle(reservation);
    final description = libraryTaskDescription(reservation);

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
      task.description = description;
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
    // 描述只在"还是我们生成的那份"时才刷新：用户改过就留着（和子待办一个道理）。
    // 老版本的描述是「来自图书馆预约（8）」，也要能被升级掉，否则长标题永远进不了描述。
    if (existing.description.isEmpty ||
        existing.description.startsWith(kLibraryDescriptionPrefix) ||
        existing.description.startsWith(kLegacyDescriptionPrefix)) {
      if (existing.description != description) {
        existing.description = description;
        touched = true;
      }
    }
    if (existing.startTime == null ||
        !existing.startTime!.isAtSameMomentAs(start)) {
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

  final wanted =
      byId.values.where((r) => libraryReservationWanted(r, now: at)).length;
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
