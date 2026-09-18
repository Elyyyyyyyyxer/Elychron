import 'package:celechron/model/task.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/page/task/task_edit_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ===== 待办搜索（2026-09-18，用户要求）=====
///
/// 待办一多就得靠翻页找，这里给一个搜索入口：
/// 顶部搜索框（iOS 那种 CupertinoSearchTextField），下面出结果，点一条进详情。
///
/// 为什么**不**复用待办页现有的筛选器：那个筛的是"类型 / 标签 / 时间"，
/// 属于"我知道我要什么、只是缩小范围"；搜索是"我只记得几个字"，
/// 搜的范围要跨全部标签页（待我处理 / 已处理 / 星标都搜），否则用户还得先想"它在哪个页签里"。
/// 打开搜索页。全集从全局 taskList 取（和待办页用的是同一份数据）。
Future<void> openTaskSearch(BuildContext context) async {
  List<Task> tasks = const <Task>[];
  try {
    tasks = List<Task>.from(Get.find<RxList<Task>>(tag: 'taskList'));
  } catch (_) {
    // 拿不到就当空列表，页面会提示"没有找到"
  }
  await Navigator.of(context, rootNavigator: true).push<void>(
    CupertinoPageRoute<void>(
      builder: (BuildContext context) => TaskSearchPage(tasks: tasks),
    ),
  );
}

class TaskSearchPage extends StatefulWidget {
  /// 待办全集（一般传全局的 taskList）
  final List<Task> tasks;

  const TaskSearchPage({super.key, required this.tasks});

  @override
  State<TaskSearchPage> createState() => _TaskSearchPageState();
}

class _TaskSearchPageState extends State<TaskSearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Task> get _results => searchTasks(widget.tasks, _query);

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return CupertinoPageScaffold(
      backgroundColor: pageBackground(context),
      navigationBar: CupertinoNavigationBar(
        middle: CupertinoSearchTextField(
          controller: _controller,
          autofocus: true,
          placeholder: '搜标题、描述、标签',
          onChanged: (value) => setState(() => _query = value),
          onSubmitted: (value) => setState(() => _query = value),
        ),
        border: null,
      ),
      child: SafeArea(
        child: _query.trim().isEmpty
            ? _hint('输入几个字就能找到那条待办（标题、描述、标签都能搜）', labelColor)
            : (results.isEmpty
                ? _hint('没有找到匹配的待办', labelColor)
                : ListView.separated(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: results.length,
                    separatorBuilder: (context, index) => Container(
                      height: 0.5,
                      margin: const EdgeInsets.only(left: 20),
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.separator, context),
                    ),
                    itemBuilder: (BuildContext context, int index) =>
                        _row(context, results[index], labelColor),
                  )),
      ),
    );
  }

  Widget _hint(String text, Color labelColor) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: labelColor),
          ),
        ),
      );

  Widget _row(BuildContext context, Task task, Color labelColor) {
    final name = task.summary.trim().isEmpty ? '(未命名待办)' : task.summary.trim();
    // 已完成 / 过期都用副标题说清楚，免得用户以为是漏掉的
    final parts = <String>[
      taskKindName[task.type] ?? '',
      if (task.status == TaskStatus.completed) '已完成',
      if (task.status != TaskStatus.completed &&
          task.endTime.isBefore(DateTime.now()))
        '已过期',
      _timeText(task),
    ].where((e) => e.isNotEmpty).toList();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute<void>(
            builder: (BuildContext context) => TaskEditPage(task),
          ),
        );
        if (mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: labelColor),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_forward, size: 16, color: labelColor),
          ],
        ),
      ),
    );
  }

  static String _timeText(Task task) {
    final time = task.isEvent ? task.startTime : task.endTime;
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final clock = two(time.hour) + ':' + two(time.minute);
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return '今天 ' + clock;
    }
    return (time.month).toString() + ' 月 ' + (time.day).toString() + ' 日';
  }
}

/// 搜索：一条待办是否匹配关键词（**纯函数，有单测**）。
///
/// 匹配范围：标题、描述、标签、评论内容。
/// - 空关键词 → 不匹配任何东西（调用方负责"没输关键词就不显示结果"）
/// - 大小写不敏感（英文课程名/标签常见大小写不一致）
/// - 多个空格分隔的词要**全部命中**（"数学 作业" 比 "数学作业" 更好用）
List<Task> searchTasks(List<Task> tasks, String query) {
  final keywords = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (keywords.isEmpty) return const <Task>[];
  final result = <Task>[];
  for (final task in tasks) {
    final haystack = taskSearchText(task);
    if (haystack.isEmpty) continue;
    if (keywords.every(haystack.contains)) result.add(task);
  }
  // 越新的排前面（最近动过的更容易是用户要找的那条）；
  // updatedAt 可空，用"创建时间 → 结束时间"兜底，保证排序键一定有值。
  DateTime sortKey(Task task) =>
      task.updatedAt ?? task.createdAt ?? task.endTime;
  result.sort((a, b) => sortKey(b).compareTo(sortKey(a)));
  return result;
}

/// 一条待办参与搜索的文本（小写、拼在一起）
String taskSearchText(Task task) {
  final parts = <String>[
    task.summary,
    task.description,
    task.tags.join(' '),
    for (final comment in task.comments) comment.content,
    for (final sub in task.subtasks) sub.title,
  ];
  return parts.where((e) => e.isNotEmpty).join('\n').toLowerCase();
}
