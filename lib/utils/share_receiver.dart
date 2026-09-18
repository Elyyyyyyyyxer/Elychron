import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/services.dart';

/// 从其它应用分享过来的一条内容：文本 或 一个文件（图片/文档…）。
class SharedItem {
  final String? text;
  final String? path;
  final String? name;
  final String? mime;

  /// 原生侧明确报上来的失败原因（目前只有 'unreadable'：那个 URI 读不出来）
  ///
  /// 为什么要留着它：以前附件复制失败会被悄悄跳过，整条分享什么都不弹，
  /// 用户以为分享功能坏了（2026-09-17 用户报的就是这个）。
  final String? error;

  const SharedItem({this.text, this.path, this.name, this.mime, this.error});

  /// 这一项是不是"读不出来的附件"
  bool get isUnreadable => error == 'unreadable';
}

/// 接收系统分享面板发来的内容（由原生 MainActivity 转交）。
class ShareReceiver {
  ShareReceiver._();

  static const MethodChannel _method = MethodChannel('celechron/share');
  static const EventChannel _event = EventChannel('celechron/share/stream');

  /// 冷启动时被分享进来的内容（没有则返回空列表）
  static Future<List<SharedItem>> getInitial() async {
    // 桌面端没有"从别的应用分享进来"这个入口（原生侧也没实现通道），直接当没有
    if (!PlatformFeatures.canReceiveShares) return const <SharedItem>[];
    try {
      final raw = await _method.invokeMethod<List<dynamic>>('getInitialShared');
      return _parse(raw);
    } catch (_) {
      return const <SharedItem>[];
    }
  }

  /// 应用已在前台时被分享进来的内容
  static Stream<List<SharedItem>> get stream =>
      !PlatformFeatures.canReceiveShares
          ? const Stream<List<SharedItem>>.empty()
          : _event.receiveBroadcastStream().map((event) {
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
        error: entry['error'] as String?,
      ));
    }
    return result;
  }
}
