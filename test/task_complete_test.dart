import 'package:celechron/model/task.dart';
import 'package:celechron/utils/task_complete.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Task buildTask({List<String> subtasks = const []}) {
    final end = DateTime(2030, 1, 1, 23, 59);
    final task = Task(
      summary: '测试待办',
      endTime: end,
      startTime: end,
      repeatEndsTime: DateTime(2030, 1, 1),
    );
    task.reset();
    task.summary = '测试待办';
    task.startTime = end;
    task.endTime = end;
    task.repeatEndsTime = DateTime(2030, 1, 1);
    task.status = TaskStatus.running;
    for (final title in subtasks) {
      task.subtasks.add(SubTask(title: title));
    }
    return task;
  }

  /// 挂一个按钮，点它等于触发「完成」检查
  Future<void> pumpButton(
    WidgetTester tester,
    Task task,
    void Function(bool) onResult,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () async {
              onResult(await confirmCompleteTask(context, task));
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('没有子待办时直接完成，不弹窗', (tester) async {
    final task = buildTask();
    bool? result;
    await pumpButton(tester, task, (value) => result = value);

    expect(result, isTrue);
    expect(find.text('还有子待办没完成'), findsNothing);
  });

  testWidgets('子待办全部完成时不弹窗', (tester) async {
    final task = buildTask(subtasks: ['a', 'b']);
    for (final subtask in task.subtasks) {
      subtask.done = true;
    }
    bool? result;
    await pumpButton(tester, task, (value) => result = value);

    expect(result, isTrue);
    expect(find.text('还有子待办没完成'), findsNothing);
  });

  testWidgets('还有子待办未完成时弹窗，确认后全部勾上', (tester) async {
    final task = buildTask(subtasks: ['a', 'b', 'c']);
    task.subtasks.first.done = true;

    bool? result;
    await pumpButton(tester, task, (value) => result = value);

    // 此时弹窗出现、还没选
    expect(find.text('还有子待办没完成'), findsOneWidget);
    expect(find.textContaining('还有 2 个子待办未完成'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.text('全部完成'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(task.subtasks.every((subtask) => subtask.done), isTrue);
  });

  testWidgets('弹窗里点取消则不完成，子待办保持原样', (tester) async {
    final task = buildTask(subtasks: ['a', 'b']);

    bool? result;
    await pumpButton(tester, task, (value) => result = value);
    expect(find.text('还有子待办没完成'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(task.subtasks.any((subtask) => subtask.done), isFalse);
  });
}
