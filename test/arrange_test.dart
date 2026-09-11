import 'package:celechron/algorithm/arrange.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// 排程死循环的回归测试。
///
/// 背景：`lib/algorithm/arrange.dart` 的 `findSolution` 里有一个
/// `while (cur.timeSpent < cur.timeNeeded)`，它靠「timeSpent 增长 + ableList 变短」
/// 来终止。但切分长度 `thisCut` 为 0（工作时长设成 0）或为负（时段 endTime <= startTime）
/// 时：timeSpent 不增长、startTime 不移动，而剩余时段又被加回 ableList ——
/// 同一段被反复取出塞回，形成**死循环**。
///
/// 这个函数由「接下来」页每秒重算排程时调用，一旦触发就是界面彻底卡死、只能重启，
/// 而且**不崩溃、不产生 ANR**，所以 logcat 里什么都看不到（这就是当初定位不到的原因）。
///
/// 有了这些用例，真回归时测试会超时失败，而不是让用户卡死。
void main() {
  Task makeTask() {
    final start = DateTime(2026, 9, 11, 9, 0);
    final end = DateTime(2026, 9, 13, 9, 0);
    final task = Task(
      summary: '写报告',
      endTime: end,
      startTime: start,
      repeatEndsTime: end,
    );
    task.isBreakable = true;
    task.timeNeeded = const Duration(hours: 4);
    task.status = TaskStatus.running;
    return task;
  }

  Period makeSlot({Duration length = const Duration(hours: 3)}) {
    final start = DateTime(2026, 9, 11, 10, 0);
    return Period(
      fromUid: 'slot',
      type: PeriodType.user,
      description: '',
      startTime: start,
      endTime: start.add(length),
      location: '',
      summary: '空闲时段',
    );
  }

  group('排程不会卡死（回归）', () {
    test('工作时长为 0：返回无解，而不是无限循环', () {
      final result = getTimeAssignSet(
        Duration.zero,
        const Duration(minutes: 5),
        <Task>[makeTask()],
        <Period>[makeSlot()],
      );
      expect(result.isValid, isFalse);
    });

    test('时段长度为 0：返回无解', () {
      final result = getTimeAssignSet(
        const Duration(minutes: 25),
        const Duration(minutes: 5),
        <Task>[makeTask()],
        <Period>[makeSlot(length: Duration.zero)],
      );
      expect(result.isValid, isFalse);
    });

    test('时段反向（结束早于开始）：返回无解', () {
      final start = DateTime(2026, 9, 11, 12, 0);
      final badSlot = Period(
        fromUid: 'bad',
        type: PeriodType.user,
        description: '',
        startTime: start,
        endTime: start.subtract(const Duration(hours: 2)),
        location: '',
        summary: '坏时段',
      );
      final result = getTimeAssignSet(
        const Duration(minutes: 25),
        const Duration(minutes: 5),
        <Task>[makeTask()],
        <Period>[badSlot],
      );
      expect(result.isValid, isFalse);
    });

    test('没有可用时段：返回无解', () {
      final result = getTimeAssignSet(
        const Duration(minutes: 25),
        const Duration(minutes: 5),
        <Task>[makeTask()],
        <Period>[],
      );
      expect(result.isValid, isFalse);
    });

    test('参数正常时能排出来（正向用例，确保修复没把功能一起掐掉）', () {
      final result = getTimeAssignSet(
        const Duration(minutes: 25),
        const Duration(minutes: 5),
        <Task>[makeTask()],
        <Period>[makeSlot(length: const Duration(hours: 5))],
      );
      expect(result.isValid, isTrue);
      expect(result.assignSet, isNotEmpty);
    });
  });
}
