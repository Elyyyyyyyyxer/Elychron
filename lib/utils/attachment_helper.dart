import 'dart:io';

import 'package:celechron/design/dingtalk_sheet.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 附件选择：把用户选中的文件复制进应用私有目录，返回新增的附件记录。
///
/// 复制而不是直接引用原路径，是因为 Android 的分区存储下 content:// 授权
/// 可能在重启后失效，复制一份才能长期打开。
///
/// ===== MOD: 先问"图库还是文件"（用户反馈：系统文件选择器对普通用户不友好）=====
///
/// 原来的写法是 `pickFiles()`（不限类型）→ 一律打开**文档选择器**，
/// 想发一张刚拍的照片也得在目录树里翻。现在先让用户选来源：
/// - **从图库选** → `FileType.image`，系统会给图库/相册（按图片过滤，能直接看到缩略图）
/// - **从文件管理选** → 不限类型，交给手机自带的文件管理
///
/// 注意：这里刻意**不加扩展名过滤**， 按扩展名过滤会被映射成 MIME 过滤，
/// 而很多文件没有登记 MIME，会出现"文件明明在却看不见"（iCal 导入踩过这个坑）。
Future<List<TaskAttachment>> pickAttachments({BuildContext? context}) async {
  var type = FileType.any;
  // 桌面端不问"图库还是文件"：电脑上本来就是一个文件对话框，
  // 再让用户先选一次来源纯属多此一举（用户 2026-09-19 要求）。
  if (context != null && context.mounted && !PlatformFeatures.isDesktop) {
    final fromGallery = await showDingTalkSheet<bool>(
      context: context,
      title: '添加附件',
      subtitle: '图片从图库选更顺手；其它文件交给文件管理',
      options: const [
        DingTalkSheetOption(
          label: '从图库选择图片',
          subtitle: '显示相册缩略图，适合照片、截图',
          value: true,
        ),
        DingTalkSheetOption(
          label: '从文件管理选择',
          subtitle: '文档、压缩包、PDF 等任意文件',
          value: false,
        ),
      ],
    );
    if (fromGallery == null) return <TaskAttachment>[];
    type = fromGallery ? FileType.image : FileType.any;
  }

  final result = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: type,
  );
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
