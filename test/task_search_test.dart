import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_search_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// 待办搜索（2026-09-18 用户要求："应该增加一个待办搜索功能"）。
///
/// 这里锁的是**匹配规则**（纯函数，不碰界面）：
/// 搜什么、怎么算命中、结果怎么排。
void main() {
  Task makeTask({
    required String summary,
    String description = '',
    List<String> tags = const [],
    List<String> comments = const [],
    List<String> subtasks = const [],
    DateTime? updatedAt,
  }) {
    final task = Task(
      summary: summary,
      startTime: DateTime(2026, 9, 18, 23, 59),
      endTime: DateTime(2026, 9, 18, 23, 59),
      repeatEndsTime: DateTime(2026, 9, 18),
    );
    task.description = description;
    task.tags = List<String>.of(tags);
    task.comments = [
      for (final text in comments)
        TaskComment(content: text, time: DateTime(2026, 9, 18)),
    ];
    task.subtasks = [
      for (final title in subtasks) SubTask(title: title),
    ];
    task.updatedAt = updatedAt;
    return task;
  }

  final tasks = <Task>[
    makeTask(summary: '数学作业', tags: ['课程'], updatedAt: DateTime(2026, 9, 18)),
    makeTask(
        summary: '写实验报告',
        description: '物理实验第三次',
        updatedAt: DateTime(2026, 9, 17)),
    makeTask(
        summary: '买牙膏', comments: ['顺便买洗衣液'], updatedAt: DateTime(2026, 9, 16)),
    makeTask(
        summary: '线性代数复习',
        subtasks: ['看第三章', '做课后题'],
        updatedAt: DateTime(2026, 9, 15)),
  ];

  test('空关键词不返回任何东西（调用方负责"没输入就不显示"）', () {
    expect(searchTasks(tasks, ''), isEmpty);
    expect(searchTasks(tasks, '   '), isEmpty);
  });

  test('按标题命中', () {
    final result = searchTasks(tasks, '数学');
    expect(result.length, 1);
    expect(result.first.summary, '数学作业');
  });

  test('按描述、标签、评论、子待办也能命中', () {
    expect(searchTasks(tasks, '物理').first.summary, '写实验报告');
    expect(searchTasks(tasks, '课程').first.summary, '数学作业');
    expect(searchTasks(tasks, '洗衣液').first.summary, '买牙膏');
    expect(searchTasks(tasks, '第三章').first.summary, '线性代数复习');
  });

  test('多个词要全部命中（空格分隔）', () {
    expect(searchTasks(tasks, '实验 报告').length, 1);
    expect(searchTasks(tasks, '实验 数学'), isEmpty);
  });

  test('大小写不敏感（英文课名/标签常见）', () {
    final list = <Task>[makeTask(summary: 'Data Structure Lab')];
    expect(searchTasks(list, 'data structure').length, 1);
    expect(searchTasks(list, 'LAB').length, 1);
  });

  test('找不到就是空，不抛异常', () {
    expect(searchTasks(tasks, '这个词肯定没有'), isEmpty);
  });

  test('结果按"最近动过"排前面', () {
    final result = searchTasks(tasks, '');
    expect(result, isEmpty);
    final byWord = searchTasks(
      <Task>[
        makeTask(summary: '复习第一章', updatedAt: DateTime(2026, 9, 10)),
        makeTask(summary: '复习第二章', updatedAt: DateTime(2026, 9, 18)),
      ],
      '复习',
    );
    expect(byWord.first.summary, '复习第二章');
  });

  test('updatedAt 为空时不会崩（用创建时间/结束时间兜底）', () {
    final result = searchTasks(
      <Task>[makeTask(summary: '没有更新时间的一条')],
      '没有',
    );
    expect(result.length, 1);
  });
}
