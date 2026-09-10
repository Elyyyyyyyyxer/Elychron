import 'package:flutter/services.dart';

/// 从其它应用分享过来的一条内容：文本 或 一个文件（图片/文档…）。
class SharedItem {
  final String? text;
  final String? path;
  final String? name;
  final String? mime;

  const SharedItem({this.text, this.path, this.name, this.mime});
}

/// 接收系统「分享」面板发来的内容（由原生 MainActivity 转交）。
class ShareReceiver {
  ShareReceiver._();

  static const MethodChannel _method = MethodChannel('celechron/share');
  static const EventChannel _event = EventChannel('celechron/share/stream');

  /// 冷启动时被分享进来的内容（没有则返回空列表）
  static Future<List<SharedItem>> getInitial() async {
    try {
      final raw = await _method.invokeMethod<List<dynamic>>('getInitialShared');
      return _parse(raw);
    } catch (_) {
      return const <SharedItem>[];
    }
  }

  /// 应用已在前台时被分享进来的内容
  static Stream<List<SharedItem>> get stream =>
      _event.receiveBroadcastStream().map((event) {
        return _parse(event is List ? event : null);
      });

  static List<SharedItem> _parse(List<dynamic>? raw) {
    if (raw == null) return const <SharedItem>[];
    final result = <SharedItem>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      result.add(SharedItem(
        text: entry['text'] as String?,
        path: entry['path'] as String?,
        name: entry['name'] as String?,
        mime: entry['mime'] as String?,
      ));
    }
    return result;
  }
}
