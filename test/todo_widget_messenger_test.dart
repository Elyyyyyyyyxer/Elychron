import 'package:celechron/model/task.dart';
import 'package:celechron/worker/todo_widget_messenger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 14, 10, 30);

  Task task({
    required String id,
    required String title,
    required DateTime time,
    TaskType type = TaskType.deadline,
    TaskStatus status = TaskStatus.running,
    DateTime? updatedAt,
  }) {
    return Task(
      uid: id,
      summary: title,
      startTime: time,
      endTime: time,
      repeatEndsTime: DateTime(time.year, time.month, time.day),
      type: type,
      status: status,
      updatedAt: updatedAt,
    );
  }

  test('snapshot keeps pending tasks and orders nearest work first', () {
    final tasks = <Task>[
      task(
        id: 'memo-old',
        title: '旧备忘',
        time: now,
        type: TaskType.memo,
        updatedAt: now.subtract(const Duration(days: 2)),
      ),
      task(id: 'tomorrow', title: '明天的任务', time: DateTime(2026, 9, 15, 9)),
      task(
        id: 'completed',
        title: '已经完成',
        time: now,
        status: TaskStatus.completed,
      ),
      task(
        id: 'overdue-old',
        title: '更早逾期',
        time: DateTime(2026, 9, 12, 9),
        status: TaskStatus.failed,
      ),
      task(
        id: 'overdue-near',
        title: '刚刚逾期',
        time: DateTime(2026, 9, 14, 10),
        status: TaskStatus.failed,
      ),
      task(
        id: 'memo-new',
        title: '新备忘',
        time: now,
        type: TaskType.memo,
        updatedAt: now,
      ),
    ];

    final snapshot = TodoWidgetMessenger.buildSnapshot(tasks, now: now);
    final visible = snapshot['tasks']! as List<Map<String, Object>>;

    expect(snapshot['pendingCount'], 5);
    expect(visible.map((item) => item['id']), [
      'overdue-near',
      'overdue-old',
      'tomorrow',
      'memo-new',
      'memo-old',
    ]);
    expect(visible.first['overdue'], isTrue);
  });

  test('snapshot formats task kinds and day-relative times', () {
    final event = task(
      id: 'event',
      title: '晨会',
      time: DateTime(2026, 9, 14, 11),
      type: TaskType.fixed,
    )..endTime = DateTime(2026, 9, 14, 12);
    final reminder = task(
      id: 'reminder',
      title: '喝水',
      time: DateTime(2026, 9, 15, 8, 5),
      type: TaskType.remind,
    );

    final snapshot = TodoWidgetMessenger.buildSnapshot([
      event,
      reminder,
    ], now: now);
    final visible = snapshot['tasks']! as List<Map<String, Object>>;

    expect(visible[0]['time'], '今天 11:00 开始');
    expect(visible[1]['time'], '明天 08:05 提醒');
  });

  test('snapshot limits payload but keeps the total pending count', () {
    final tasks = List.generate(
      TodoWidgetMessenger.maxVisibleTasks + 2,
      (index) => task(
        id: '$index',
        title: '任务 $index',
        time: now.add(Duration(hours: index + 1)),
      ),
    );

    final snapshot = TodoWidgetMessenger.buildSnapshot(tasks, now: now);

    expect(
      snapshot['pendingCount'],
      TodoWidgetMessenger.maxVisibleTasks + 2,
    );
    expect(
      (snapshot['tasks']! as List<Map<String, Object>>).length,
      TodoWidgetMessenger.maxVisibleTasks,
    );
  });

  test('queued widget completion updates the matching task and subtasks', () {
    final target = task(id: 'target', title: '目标', time: now)
      ..subtasks = [
        SubTask(title: '步骤一'),
        SubTask(title: '步骤二', done: true),
      ];
    final untouched = task(id: 'other', title: '其他', time: now);
    final changed = TodoWidgetMessenger.markCompleted(
      [target, untouched],
      {'target', 'missing'},
      now: now,
    );

    expect(changed, isTrue);
    expect(target.status, TaskStatus.completed);
    expect(target.updatedAt, now);
    expect(target.subtasks.every((subtask) => subtask.done), isTrue);
    expect(untouched.status, TaskStatus.running);
  });

  test('queued widget completion is idempotent', () {
    final completed = task(
      id: 'completed',
      title: '已完成',
      time: now,
      status: TaskStatus.completed,
    );

    expect(
      TodoWidgetMessenger.markCompleted(
        [completed],
        {'completed'},
        now: now,
      ),
      isFalse,
    );
  });
}
