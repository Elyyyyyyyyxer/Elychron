import 'dart:async';
import 'dart:io';
import 'package:get/get.dart';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/pigeon/flow_messenger.dart';

class FlowController extends GetxController {
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final flowList = Get.find<RxList<Period>>(tag: 'flowList');
  final flowListLastUpdate = Get.find<Rx<DateTime>>(tag: 'flowListLastUpdate');
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');
  final taskListLastUpdate = Get.find<Rx<DateTime>>(tag: 'taskListLastUpdate');
  final _db = Get.find<DatabaseHelper>(tag: 'db');
  late var _scholarFlowList = scholar.value.periods;
  var timeNow = DateTime.now().obs;
  final _flowMessenger = FlowMessenger();
  Timer? _timer;
  // 数据变化时置位，下一秒执行完整 walk；平时按 _nextWalkAt 的时间边界调度

  @override
  void onInit() {
    // 把基本事项给排序好，看目前在上哪节课（和排序有关系）
    refreshScholarFlowList();

    refreshWidget();

    // 每秒只更新时钟和进行中的进度；昂贵的完整 walk 只在数据变化或时间边界时执行
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _onTick());

    // 当“学业”页面有更新（例如出现新课程），更新基本Flow列表
    ever(scholar, (callback) {
      refreshScholarFlowList();
      refreshWidget();
    });
    ever(taskList, (callback) {
      refreshWidget();
    });

    super.onInit();
  }

  void _onTick() {
    // 只更新时钟：日历页/待办页的「每秒刷新」都靠它
    timeNow.value = DateTime.now();
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  Future<void> saveFlowListToDb() async {
    await _db.setFlowList(flowList);
    await _db.setFlowListUpdateTime(flowListLastUpdate.value);
  }

  void loadFlowListLastUpdate() {
    flowListLastUpdate.value = _db.getFlowListUpdateTime();
  }

  bool isFlowListOutdated() {
    return flowListLastUpdate.value.isBefore(taskListLastUpdate.value);
  }

  void updateDeadlineListTime() {
    flowListLastUpdate.value = taskListLastUpdate.value.copyWith();
    // “规划方案已过期”横幅的忽略操作只走这里，需立即持久化，重启后横幅才不会复现
    _db.setFlowListUpdateTime(flowListLastUpdate.value);
  }

  // 生成新的安排

  // 根据安排走，已完成的就剔除

  /* 同步Flow页面的任务进度到Task页面 */

  void refreshScholarFlowList() {
    _scholarFlowList = scholar.value.periods;
    _scholarFlowList.sort((a, b) {
      return a.startTime.compareTo(b.startTime);
    });
  }

  void refreshWidget() {
    // 只有 iOS 需要向原生小组件发送数据，其他平台不必构建 DTO
    if (!Platform.isIOS) return;
    List<PeriodDto?>? flowListDto =
        flowList.where((e) => e.type == PeriodType.flow).map((e) {
      return PeriodDto(
        uid: e.uid,
        type: PeriodTypeDto.flow,
        name: e.summary,
        startTime: e.startTime.millisecondsSinceEpoch ~/ 1000,
        endTime: e.endTime.millisecondsSinceEpoch ~/ 1000,
        location: e.location,
      );
    }).toList();
    flowListDto.addAll(_scholarFlowList
        .map((e) => PeriodDto(
              uid: e.uid,
              type: e.type == PeriodType.classes
                  ? PeriodTypeDto.classes
                  : PeriodTypeDto.test,
              name: e.summary,
              startTime: e.startTime.millisecondsSinceEpoch ~/ 1000,
              endTime: e.endTime.millisecondsSinceEpoch ~/ 1000,
              location: e.type == PeriodType.classes
                  ? e.location.replaceAll(RegExp(r'[(（].*录播.*[)）]'), '')
                  : e.location,
            ))
        .toList());
    for (var task in taskList.where((e) => e.type == TaskType.fixed)) {
      DateTime time = DateTime.now();
      DateTime? last;
      for (int i = 0; i < 5; i++) {
        Period? period = task.deadlineOfTime(time, predicting: true);
        if (period != null) {
          if (last == null || last.compareTo(period.startTime) != 0) {
            flowListDto.add(PeriodDto(
              uid: period.uid,
              type: PeriodTypeDto.user,
              name: task.summary,
              startTime: period.startTime.millisecondsSinceEpoch ~/ 1000,
              endTime: period.endTime.millisecondsSinceEpoch ~/ 1000,
              location: task.location,
            ));
            last = period.startTime.copyWith();
          }
        }
        time = time.add(Duration(days: task.repeatPeriod));
      }
    }

    if (Platform.isIOS) {
      _flowMessenger.transfer(FlowMessage(flowListDto: flowListDto));
    }
  }
}
