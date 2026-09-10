import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:share_plus/share_plus.dart';

const Set<String> _imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.bmp',
  '.heic',
  '.heif',
};

bool isImageFile(String path) {
  final lower = path.toLowerCase();
  return _imageExtensions.any(lower.endsWith);
}

/// 附件缩略图：图片返回缩略图，其它类型返回 null（调用方用图标代替）。
Widget? attachmentThumbnail(String path, {double size = 36}) {
  if (!isImageFile(path)) return null;
  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * 3).toInt(),
      errorBuilder: (context, error, stackTrace) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemFill, context),
        child: Icon(CupertinoIcons.photo,
            size: size * 0.5, color: CupertinoColors.inactiveGray),
      ),
    ),
  );
}

/// 全屏查看图片，支持双指缩放与分享。
Future<void> showImagePreview(
  BuildContext context, {
  required String path,
  required String name,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    CupertinoPageRoute<void>(
      fullscreenDialog: true,
      builder: (BuildContext context) =>
          _ImagePreviewPage(path: path, name: name),
    ),
  );
}

class _ImagePreviewPage extends StatelessWidget {
  final String path;
  final String name;

  const _ImagePreviewPage({required this.path, required this.name});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black,
        middle: Text(
          name,
          style: const TextStyle(color: CupertinoColors.white, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.xmark, color: CupertinoColors.white),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            SharePlus.instance.share(
              ShareParams(files: [XFile(path)], subject: name),
            );
          },
          child: const Icon(CupertinoIcons.share, color: CupertinoColors.white),
        ),
        border: null,
      ),
      child: SafeArea(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Center(
            child: Image.file(
              File(path),
              errorBuilder: (context, error, stackTrace) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.exclamationmark_triangle,
                      color: CupertinoColors.systemYellow, size: 40),
                  SizedBox(height: 12),
                  Text('图片无法打开',
                      style: TextStyle(color: CupertinoColors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
