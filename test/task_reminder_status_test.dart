import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/flow/flow_controller.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/page/task/task_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _TaskController extends TaskController {
  @override
  void onInit() {}
}

class _FlowController extends FlowController {
  @override
  void onInit() {}
}

Task reminder(DateTime at) => Task(
      summary: '测试提醒',
      type: TaskType.remind,
      startTime: at,
      endTime: at.add(const Duration(hours: 8)),
      repeatEndsTime: at,
      reminderEnabled: true,
      reminderTime: at,
    );

void main() {
  tearDown(() => Get.reset());

  test('提醒倒计时使用实际提醒时间，保留未完成状态', () {
    final task = reminder(DateTime.now().subtract(const Duration(minutes: 2)));
    expect(task.timeStatus!.text, startsWith('提醒已过'));
    expect(task.timeStatus!.urgent, isFalse);
    expect(task.status, TaskStatus.running);
  });

  testWidgets('卡片在实际提醒时刻更新，不能等到隐藏的结束时间', (tester) async {
    final at = DateTime(2026, 10, 6, 12, 24);
    final task = reminder(at);
    Get.put(DatabaseHelper(), tag: 'db');
    Get.put(Scholar().obs, tag: 'scholar');
    Get.put(<Period>[].obs, tag: 'flowList');
    Get.put(at.obs, tag: 'flowListLastUpdate');
    Get.put(<Task>[task].obs, tag: 'taskList');
    Get.put(at.obs, tag: 'taskListLastUpdate');
    Get.put<TaskController>(_TaskController());
    final flow = Get.put<FlowController>(_FlowController());
    flow.timeNow.value = at.subtract(const Duration(seconds: 1));
    final page = TaskPage();
    await tester.pumpWidget(CupertinoApp(
      home: Builder(
        builder: (context) => CupertinoPageScaffold(
          child:
              page.createCard(context, task, CupertinoColors.systemBlue, null),
        ),
      ),
    ));
    expect(find.text('待提醒'), findsOneWidget);

    flow.timeNow.value = at;
    await tester.pump();
    expect(find.text('已提醒'), findsOneWidget);
    expect(find.text('待提醒'), findsNothing);

    flow.timeNow.value = at.add(const Duration(minutes: 1));
    await tester.pump();
    expect(find.text('已提醒'), findsOneWidget);
    expect(task.status, TaskStatus.running);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
