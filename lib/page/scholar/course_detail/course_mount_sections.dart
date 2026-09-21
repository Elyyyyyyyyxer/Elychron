import 'dart:io';

import 'package:celechron/design/dingtalk_menu.dart';
import 'package:celechron/design/context_menu.dart';
import 'package:celechron/design/app_route.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/sub_title.dart';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/course_mount_store.dart';
import 'package:celechron/mod/course_mount_tombstone.dart';
import 'package:celechron/model/course_mount.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/page/task/task_controller.dart';
import 'package:celechron/page/task/task_create_page.dart';
import 'package:celechron/utils/attachment_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// 课程挂载：**资料 / 评论 / 关联待办** 三个区块。
///
/// 需求与拍板决定见 `docs/BACKLOG.md` #24：评论与资料挂在**课程总体**上
/// （键 = 课程代码），"某个待办也可以挂到课程上"则走 `Task.courseId`
///， 于是这门课的待办是**查出来的**，不在这里冗余存一份。
///
/// 三个区块各自是独立的小组件（自带状态），这样课程详情页那个 StatelessWidget
/// 不用为了挂载改成 StatefulWidget，改动面最小。

// ============================================================ 资料（附件）

class CourseMaterialsSection extends StatefulWidget {
  const CourseMaterialsSection({super.key, required this.courseId});

  final String courseId;

  @override
  State<CourseMaterialsSection> createState() => _CourseMaterialsSectionState();
}

class _CourseMaterialsSectionState extends State<CourseMaterialsSection> {
  late CourseMount _mount;
  bool _busy = false;

  DatabaseHelper get _db => Get.find<DatabaseHelper>(tag: 'db');

  @override
  void initState() {
    super.initState();
    _mount = _db.courseMount(widget.courseId);
  }

  Future<void> _persist() async {
    await _db.saveCourseMount(_mount);
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final added = await pickAttachments(context: context);
      if (added.isEmpty) return;
      _mount.attachments.addAll(added);
      await _persist();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int index) async {
    // 记墓碑：否则另一端同步时会把这条资料原样带回来（用户要求补全墓碑）
    final removedAttachment = _mount.attachments[index];
    await CourseMountTombstone.remember(CourseMountTombstone.attachmentKey(
        _mount.courseId, removedAttachment.path));
    _mount.attachments.removeAt(index);
    await _persist();
  }

  Future<void> _open(TaskAttachment attachment) async {
    try {
      await openAttachment(context, attachment);
    } catch (_) {
      // 文件被清理掉了之类：说一句人话，别抛异常
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('打不开这个附件'),
          content: const Text('文件可能已被删除或移动。'),
          actions: [
            CupertinoDialogAction(
              child: const Text('知道了'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Column(
      children: [
        SubSubtitleRow(subtitle: '资料'),
        RoundRectangleCard(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            children: [
              if (_mount.attachments.isEmpty)
                // 左对齐：Column 默认是居中的，这行提示语原来被摆在卡片中间，
                // 与下面的按钮不在一条线上（用户看图指出来的）。
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '课件、笔记、板书……都可以放这里',
                      style: TextStyle(fontSize: 13, color: labelColor),
                    ),
                  ),
                ),
              for (var i = 0; i < _mount.attachments.length; i++)
                _attachmentRow(context, i, labelColor),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: CupertinoButton(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: CupertinoColors.systemBlue.withValues(alpha: 0.12),
                  onPressed: _busy ? null : _add,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.paperclip,
                          size: 16, color: CupertinoColors.systemBlue),
                      const SizedBox(width: 6),
                      Text(
                        _busy ? '正在添加…' : '添加图片 / 文件',
                        style: const TextStyle(
                            fontSize: 14, color: CupertinoColors.systemBlue),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _attachmentRow(BuildContext context, int index, Color labelColor) {
    final item = _mount.attachments[index];
    final size = formatFileSize(item.size);
    final isImage = _isImage(item.name);
    // 图片能预览就预览（2026-09-17 用户要求）：这一块本来就是放课件和板书照片的，
    // 只给一个文件名 + 图标的话，用户得一个个点开才知道哪张是哪张。
    final previewable = isImage && _previewFile(item) != null;
    return contextMenuRegion(
      behavior: HitTestBehavior.opaque,
      onTap: () => previewable ? _preview(item) : _open(item),
      // CupertinoListTile 那套用不上，重命名/删除走长按菜单
      onLongPress: () => _showActions(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            if (previewable)
              _thumbnail(item)
            else
              Icon(
                isImage ? CupertinoIcons.photo : CupertinoIcons.doc_text,
                size: 18,
                color: CupertinoColors.systemBlue,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  Text(
                    size.isEmpty
                        ? (previewable ? '点一下看大图 · 长按可重命名' : '长按可重命名')
                        : '$size · 长按可重命名',
                    style: TextStyle(fontSize: 11, color: labelColor),
                  ),
                ],
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 32),
              onPressed: () => _remove(index),
              child:
                  Icon(CupertinoIcons.clear_thick, size: 16, color: labelColor),
            ),
          ],
        ),
      ),
    );
  }

  /// 附件在磁盘上真实存在吗（被清理掉过就退回到图标）
  File? _previewFile(TaskAttachment item) {
    try {
      final file = File(item.path);
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// 小缩略图（48×48，圆角），失败时退回到图标
  Widget _thumbnail(TaskAttachment item) {
    final file = _previewFile(item);
    if (file == null) {
      return const Icon(CupertinoIcons.photo,
          size: 18, color: CupertinoColors.systemBlue);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        file,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: 46,
          height: 46,
          color: CupertinoColors.systemGrey5,
          child: const Icon(CupertinoIcons.photo,
              size: 18, color: CupertinoColors.systemBlue),
        ),
      ),
    );
  }

  /// 点开图片：全屏看，可以捏合放大（把图存下来看板书用）
  Future<void> _preview(TaskAttachment item) async {
    final file = _previewFile(item);
    if (file == null) {
      await _open(item);
      return;
    }
    await Navigator.of(context, rootNavigator: true).push<void>(
      appPageRoute<void>(
        fullscreenDialog: true,
        builder: (BuildContext context) => _CourseImagePreview(
          file: file,
          title: item.name,
        ),
      ),
    );
  }

  /// 长按：重命名 / 打开 / 删除
  Future<void> _showActions(int index) async {
    final item = _mount.attachments[index];
    await showDingTalkMenu(
      context,
      title: item.name,
      items: [
        DingTalkMenuItem(
          label: '重命名',
          icon: CupertinoIcons.pencil,
          onTap: () => _rename(index),
        ),
        DingTalkMenuItem(
          label: '用其它应用打开',
          icon: CupertinoIcons.arrow_up_right_square,
          onTap: () => _open(item),
        ),
        DingTalkMenuItem(
          label: '删除',
          icon: CupertinoIcons.trash,
          onTap: () => _remove(index),
        ),
      ],
    );
  }

  /// 重命名附件
  ///
  /// 只改**显示名**（`TaskAttachment.name`），不动磁盘上的文件名 ——
  /// 磁盘名是当初复制进来时定的，改它要动文件系统、还可能撞名，
  /// 而用户真正想要的就是"列表里那行叫什么"。
  Future<void> _rename(int index) async {
    final item = _mount.attachments[index];
    final dot = item.name.lastIndexOf('.');
    final extension = dot > 0 ? item.name.substring(dot) : '';
    final base = dot > 0 ? item.name.substring(0, dot) : item.name;
    final controller = TextEditingController(text: base);
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('重命名'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                placeholder: '新名字',
                onSubmitted: (value) => Navigator.of(context).pop(value),
              ),
              if (extension.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('后缀 $extension 会保留',
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('保存'),
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _mount.attachments[index].name = '$trimmed$extension';
    await _persist();
  }

  /// 课程资料里的一张图：全屏看，能捏合、能拖动。
  ///
  /// 为什么不用系统看图应用：板书照片经常要放大对细节，跳出去还得再跳回来，
  /// 而且在应用内看没有"这个文件会不会被别的应用读走"的顾虑。
  static bool _isImage(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic');
  }
}

// ================================================================ 评论

class CourseCommentsSection extends StatefulWidget {
  const CourseCommentsSection({super.key, required this.courseId});

  final String courseId;

  @override
  State<CourseCommentsSection> createState() => _CourseCommentsSectionState();
}

class _CourseCommentsSectionState extends State<CourseCommentsSection> {
  late CourseMount _mount;
  final _controller = TextEditingController();

  DatabaseHelper get _db => Get.find<DatabaseHelper>(tag: 'db');

  @override
  void initState() {
    super.initState();
    _mount = _db.courseMount(widget.courseId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    _mount.comments.add(TaskComment(content: content, time: DateTime.now()));
    _controller.clear();
    await _db.saveCourseMount(_mount);
    if (mounted) setState(() {});
  }

  Future<void> _remove(int index) async {
    // 记墓碑（评论没有 uid，用"内容+时间"当身份）
    final removedComment = _mount.comments[index];
    await CourseMountTombstone.remember(CourseMountTombstone.commentKey(
        _mount.courseId,
        removedComment.content,
        removedComment.time.millisecondsSinceEpoch));
    _mount.comments.removeAt(index);
    await _db.saveCourseMount(_mount);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    // 新的评论排在上面（最近记的最有用）
    final comments = _mount.comments.reversed.toList();
    return Column(
      children: [
        SubSubtitleRow(subtitle: '评论'),
        RoundRectangleCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: CupertinoTextField(
                      controller: _controller,
                      placeholder: '这门课记点什么…',
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(32, 32),
                    onPressed: _add,
                    child: const Icon(CupertinoIcons.arrow_up_circle_fill,
                        size: 26, color: CupertinoColors.systemBlue),
                  ),
                ],
              ),
              if (comments.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('还没有评论',
                        style: TextStyle(fontSize: 13, color: labelColor)),
                  ),
                ),
              for (var i = 0; i < comments.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(comments[i].content,
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                              _stamp(comments[i].time),
                              style: TextStyle(fontSize: 11, color: labelColor),
                            ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(30, 30),
                        // 注意：显示顺序是反的，删除时要换算回原始下标
                        onPressed: () =>
                            _remove(_mount.comments.length - 1 - i),
                        child: Icon(CupertinoIcons.clear_thick,
                            size: 16, color: labelColor),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    final clock = '${two(time.hour)}:${two(time.minute)}';
    return sameDay ? '今天 $clock' : '${time.month} 月 ${time.day} 日 $clock';
  }
}

// ============================================================ 关联待办

class CourseTasksSection extends StatefulWidget {
  const CourseTasksSection({super.key, required this.courseId});

  final String courseId;

  @override
  State<CourseTasksSection> createState() => _CourseTasksSectionState();
}

class _CourseTasksSectionState extends State<CourseTasksSection> {
  Future<void> _create() async {
    final controller = Get.isRegistered<TaskController>()
        ? Get.find<TaskController>()
        : Get.put(TaskController());

    final now = DateTime.now();
    final draft = Task(endTime: now, startTime: now, repeatEndsTime: now)
      ..reset()
      ..courseId = widget.courseId; // 关键：预挂到这门课
    draft.startTime = now.copyWith();
    draft.endTime = now.copyWith();
    draft.repeatEndsTime = now.copyWith();
    draft.status = TaskStatus.running;

    final created = await showCupertinoModalPopup<Task>(
      context: context,
      builder: (BuildContext context) => TaskCreatePage(draft),
    );
    if (created == null || created.status == TaskStatus.deleted) return;
    controller.taskList.add(created);
    controller.updateDeadlineList();
    controller.updateDeadlineListTime();
    controller.taskList.refresh();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final tasks = Get.isRegistered<RxList<Task>>(tag: 'taskList')
        ? Get.find<RxList<Task>>(tag: 'taskList')
        : <Task>[].obs;
    return Obx(() {
      final mine = tasksForCourse(tasks, widget.courseId);
      return Column(
        children: [
          SubSubtitleRow(subtitle: '相关待办'),
          RoundRectangleCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                if (mine.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '这门课还没有挂待办',
                        style: TextStyle(fontSize: 13, color: labelColor),
                      ),
                    ),
                  ),
                for (final task in mine) _taskRow(context, task, labelColor),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: CupertinoColors.systemBlue.withValues(alpha: 0.12),
                    onPressed: _create,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.add,
                            size: 16, color: CupertinoColors.systemBlue),
                        SizedBox(width: 6),
                        Text('新建待办并挂到这门课',
                            style: TextStyle(
                                fontSize: 14,
                                color: CupertinoColors.systemBlue)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _taskRow(BuildContext context, Task task, Color labelColor) {
    final done = task.status == TaskStatus.completed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? CupertinoIcons.checkmark_circle : CupertinoIcons.circle,
            size: 18,
            color: done ? CupertinoColors.systemGreen : labelColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task.summary.isEmpty ? '未命名待办' : task.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? labelColor : null,
              ),
            ),
          ),
          Text(
            task.isMemo ? '备忘' : _due(task),
            style: TextStyle(fontSize: 12, color: labelColor),
          ),
        ],
      ),
    );
  }

  static String _due(Task task) {
    String two(int value) => value.toString().padLeft(2, '0');
    final time = task.isEvent ? task.startTime : task.endTime;
    final now = DateTime.now();
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    final clock = '${two(time.hour)}:${two(time.minute)}';
    if (sameDay) return '今天 $clock';
    return '${time.month} 月 ${time.day} 日';
  }
}

/// 附件路径是否还存在（给"打不开"提示用；这里只做展示判断，不做 IO）
bool attachmentFileExists(TaskAttachment attachment) =>
    File(attachment.path).existsSync();

/// ===== 课程资料图片的全屏预览 =====
///
/// 为什么不用系统看图应用：板书照片经常要放大对细节，跳出去再跳回来很烦；
/// 而且应用内看没有"这个文件会不会被别的应用读走"的顾虑。
class _CourseImagePreview extends StatelessWidget {
  const _CourseImagePreview({required this.file, required this.title});

  final File file;
  final String title;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black,
        border: null,
        middle: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, color: CupertinoColors.white),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child:
              const Text('完成', style: TextStyle(color: CupertinoColors.white)),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 6,
                child: Center(
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => const Text(
                      '这张图打不开了',
                      style: TextStyle(color: CupertinoColors.white),
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Text(
                '捏合放大 · 拖动查看',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemGrey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
