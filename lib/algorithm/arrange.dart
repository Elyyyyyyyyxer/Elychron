import 'package:celechron/model/task.dart';
// ===== MOD: 循环保护（防卡死）=====
import 'package:celechron/mod/loop_guard.dart';
import 'package:celechron/model/period.dart';

class TimeAssignSet {
  bool isValid;
  Duration restTime;
  List<Period> assignSet;

  TimeAssignSet({
    this.isValid = false,
    this.restTime = const Duration(minutes: 15),
    this.assignSet = const [],
  });
}

TimeAssignSet findSolution(Duration workTime, Duration targetRestTime,
    List<Task> deadlineList_, List<Period> ableList_) {
  List<Task> deadlineList = [];
  List<Period> ableList = [];

  for (var x in deadlineList_) {
    deadlineList.add(x.copyWith());
  }
  for (var x in ableList_) {
    ableList.add(x.copyWith());
  }
  for (var x in ableList) {
    x.genUid();
  }

  deadlineList.sort((a, b) => a.endTime.compareTo(b.endTime));
  ableList.sort(comparePeriod);
  ableList = List.from(ableList.reversed);

  Map<String, bool> isFresh = {};
  for (Period period in ableList) {
    isFresh[period.uid] = true;
  }

  TimeAssignSet ans = TimeAssignSet(
    isValid: true,
    restTime: targetRestTime,
    assignSet: [],
  );

  for (Task cur in deadlineList) {
    if (targetRestTime <= Duration.zero) cur.isBreakable = false;
    bool isStarting = cur.isBreakable;

    final guard = LoopGuard('排程 findSolution');
    while (cur.timeSpent < cur.timeNeeded) {
      if (guard.tick()) {
        ans.isValid = false;
        return ans;
      }
      if (ableList.isEmpty) {
        ans.isValid = false;
        return ans;
      }

      Period now = ableList.removeLast();

      if (isStarting) {
        if (!isFresh[now.uid]!) {
          now.startTime = now.startTime.add(targetRestTime);
        }
        isStarting = false;
      }

      Duration curLength = cur.timeNeeded - cur.timeSpent;
      Duration nowLength = now.endTime.difference(now.startTime);
      Duration thisCut = curLength < nowLength ? curLength : nowLength;
      if (cur.isBreakable) {
        thisCut = thisCut < workTime ? thisCut : workTime;
      }

      // ===== MOD: 防止界面卡死 =====
      // 这个 while 靠「timeSpent 增长 + ableList 变短」来终止。但当下面的
      // thisCut 为 0（工作时长设成 0）或为负（时段数据 endTime <= startTime）时，
      // timeSpent 不增长、now.startTime 不移动，而第 94 行又把这段剩余时段加回
      // ableList —— 同一段被反复取出塞回，形成**死循环**，表现就是"用着用着突然
      // 卡死只能重启"（该函数由「接下来」页每秒重算排程时调用）。
      // 这里直接判为无解返回，让界面显示"排不下"，而不是卡死。
      if (thisCut <= Duration.zero) {
        ans.isValid = false;
        return ans;
      }
      if (now.startTime.add(thisCut).isAfter(cur.endTime)) {
        ans.isValid = false;
        return ans;
      }

      Period period = Period(
        fromUid: cur.uid,
        type: PeriodType.flow,
        description: cur.description,
        startTime: now.startTime,
        endTime: now.startTime.add(thisCut),
        location: cur.location,
        summary: cur.summary,
      );
      period.genUid();
      ans.assignSet.add(period);
      cur.timeSpent += thisCut;
      now.startTime = now.startTime.add(thisCut);
      if (cur.isBreakable) {
        now.startTime = now.startTime.add(targetRestTime);
      }

      isFresh[now.uid] = cur.isBreakable && (cur.timeSpent >= cur.timeNeeded);
      if (now.startTime.isBefore(now.endTime)) {
        ableList.add(now);
      }
    }
  }

  return ans;
}

TimeAssignSet getTimeAssignSet(Duration workTime, Duration restTime,
    List<Task> deadlineList, List<Period> ableList) {
  TimeAssignSet ans = findSolution(workTime, restTime, deadlineList, ableList);
  if (ans.isValid) return ans;

  int l = 0, r = restTime.inMinutes - 1;
  while (r >= l) {
    int mid = (l + r) ~/ 2;
    TimeAssignSet res =
        findSolution(workTime, Duration(minutes: mid), deadlineList, ableList);
    if (res.isValid) {
      l = mid + 1;
      ans = res;
    } else {
      r = mid - 1;
    }
  }

  if (!ans.isValid) ans.assignSet = [];
  return ans;
}
