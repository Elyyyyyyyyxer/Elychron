import 'dart:convert';
import 'dart:io';

/// ============ 图片 → 模型可吃的格式 ============
///
/// 官方文档（https://api-docs.deepseek.com/guides/vision）：
/// - `deepseek-flash` 支持图片，明确写了 "read text from screenshots"
/// - 格式支持 JPEG / PNG / GIF 等
/// - 请求体上限 **48 MiB**，base64 也算在内 → 手机截图（通常 1~4 MB）可以**原样发**，
///   不必压缩，原生质量对读中文小字最有利
/// - `image_url` 里可以带 `detail`：low（缩到 512×512，省但看不清小字）/ high / original
///   我们要读截图里的小字，所以用 `high`
class AiImagePart {
  const AiImagePart({required this.mediaType, required this.base64});

  final String mediaType;
  final String base64;

  String get dataUri => 'data:$mediaType;base64,$base64';
}

class AiImage {
  AiImage._();

  /// 我们自己的上限，比官方 48 MiB 保守得多（base64 会膨胀 1/3）
  static const int maxFileBytes = 12 * 1024 * 1024;

  /// 从本地文件读一张图；不支持的格式或过大时抛出可读的错误
  static Future<AiImagePart> fromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const FormatException('图片文件不在了，可能已被清理');
    }
    final length = await file.length();
    if (length == 0) {
      throw const FormatException('这张图是空的');
    }
    if (length > maxFileBytes) {
      throw FormatException(
        '图片太大了（${(length / 1024 / 1024).toStringAsFixed(1)} MB），'
        '超过 ${maxFileBytes ~/ 1024 ~/ 1024} MB 的图发不出去',
      );
    }

    final bytes = await file.readAsBytes();
    final mediaType = _sniff(bytes, file.path);
    return AiImagePart(mediaType: mediaType, base64: base64Encode(bytes));
  }

  /// 看文件头判断真实格式（比看扩展名可靠）
  static String _sniff(List<int> bytes, String path) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    // 退回到扩展名
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// 这个文件看起来是不是能发给模型的图片
  static bool looksLikeImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic');
  }
}
