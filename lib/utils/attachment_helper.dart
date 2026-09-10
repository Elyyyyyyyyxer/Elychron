import 'dart:io';

import 'package:celechron/model/task.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 附件选择：把用户选中的文件复制进应用私有目录，返回新增的附件记录。
///
/// 复制而不是直接引用原路径，是因为 Android 的分区存储下 content:// 授权
/// 可能在重启后失效，复制一份才能长期打开。
Future<List<TaskAttachment>> pickAttachments() async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: true);
  if (result == null || result.files.isEmpty) return <TaskAttachment>[];

  final dir = await getApplicationDocumentsDirectory();
  final attachDir = Directory('${dir.path}/task_attachments');
  if (!await attachDir.exists()) {
    await attachDir.create(recursive: true);
  }

  final added = <TaskAttachment>[];
  for (final file in result.files) {
    final source = file.path;
    if (source == null) continue;
    final destPath =
        '${attachDir.path}/${DateTime.now().microsecondsSinceEpoch}_${file.name}';
    await File(source).copy(destPath);
    added.add(TaskAttachment(
      name: file.name,
      path: destPath,
      size: file.size,
    ));
  }
  return added;
}

/// 把一个外部文件（例如其它应用分享过来的）复制进应用附件目录。
Future<TaskAttachment?> copyToAttachments(
    String sourcePath, String name) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final attachDir = Directory('${dir.path}/task_attachments');
    if (!await attachDir.exists()) {
      await attachDir.create(recursive: true);
    }
    final destPath =
        '${attachDir.path}/${DateTime.now().microsecondsSinceEpoch}_$name';
    final copied = await File(sourcePath).copy(destPath);
    return TaskAttachment(
      name: name,
      path: destPath,
      size: await copied.length(),
    );
  } catch (_) {
    return null;
  }
}

/// 用系统分享面板打开附件（Android 上比 file:// 直开可靠）。
Future<void> openAttachment(
    BuildContext context, TaskAttachment attachment) async {
  final file = File(attachment.path);
  if (!await file.exists()) {
    throw const FileSystemException('附件文件已不存在');
  }
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(attachment.path)],
      subject: attachment.name,
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// 人类可读的文件大小；未知（<=0）返回空串。
String formatFileSize(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
