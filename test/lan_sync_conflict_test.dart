import 'package:celechron/model/task.dart';
import 'package:celechron/mod/lan_sync_conflict.dart';
import 'package:flutter_test/flutter_test.dart';

/// 局域网同步的**字段级冲突**（v1.5.0，用户要求"展示冲突的字段，允许选择"）。
///
/// 背景：合并口径是整条按 updatedAt 晚者胜，所以"手机改标题、电脑改截止时间"
/// 这种场景，晚改的那条会把另一边改的字段静默盖掉。这里锁的是
/// "到底哪些字段不一致、展示成什么样"——它是给用户看的那份差异，写错了用户就选错。
void main() {
  Task make({
    String summary = '写开题报告',
    String description = '',
    String location = '',
    DateTime? start,
    DateTime? end,
    List<String> tags = const <String>[],
    bool starred = false,
    List<String> subtasks = const <String>[],
  }) {
    final task = Task(
      summary: summary,
      startTime: start ?? DateTime(2026, 9, 20, 9, 0),
      endTime: end ?? DateTime(2026, 9, 20, 18, 0),
      repeatEndsTime: DateTime(2026, 9, 20),
    );
    task.description = description;
    task.location = location;
    task.tags = List<String>.of(tags);
    task.starred = starred;
    task.subtasks = [
      for (final title in subtasks) SubTask(title: title),
    ];
    return task;
  }

  test('两条一模一样 → 没有冲突字段', () {
    expect(diffTasks(make(), make()), isEmpty);
  });

  test('只有标题不同 → 只报标题', () {
    final diff = diffTasks(make(), make(summary: '写文献综述'));
    expect(diff.keys.toList(), <String>['标题']);
    expect(diff['标题'], <String>['写开题报告', '写文献综述']);
  });

  test('两边各改一个不同字段 → 两个字段都报出来（这正是要用户挑的场景）', () {
    final diff = diffTasks(
      make(summary: '写开题报告'),
      make(summary: '写开题报告（V2）', end: DateTime(2026, 9, 25, 18, 0)),
    );
    expect(diff.containsKey('标题'), isTrue);
    expect(diff.containsKey('截止时间'), isTrue);
  });

  test('时间按可比对的格式展示（本地时间，分钟精度）', () {
    final diff = diffTasks(
      make(end: DateTime(2026, 9, 20, 18, 0)),
      make(end: DateTime(2026, 9, 21, 9, 30)),
    );
    expect(diff['截止时间']![0], contains('2026-09-20 18:00'));
    expect(diff['截止时间']![1], contains('2026-09-21 09:30'));
  });

  test('空的展示成（无），列表用顿号连接', () {
    final diff = diffTasks(
      make(tags: const <String>[], subtasks: const <String>[]),
      make(tags: <String>['课程', '论文'], subtasks: <String>['查资料', '写提纲']),
    );
    expect(diff['标签'], <String>['（无）', '课程、论文']);
    expect(diff['子待办'], <String>['（无）', '查资料、写提纲']);
  });

  test('星标这种布尔也要能看出来谁改了', () {
    final diff = diffTasks(make(starred: false), make(starred: true));
    expect(diff['星标'], <String>['否', '是']);
  });

  test('描述与地点同样参与比较', () {
    final diff = diffTasks(
      make(description: '', location: ''),
      make(description: '带电脑', location: '图书馆'),
    );
    expect(diff.containsKey('描述'), isTrue);
    expect(diff.containsKey('地点'), isTrue);
  });
}
