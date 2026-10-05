import 'package:celechron/database/database_helper.dart';
import 'package:get/get.dart';

/// ===== 图书馆预约的配置（2026-10-01）=====
///
/// token 存 optionsBox（和 PTA 的 cookie 一样，不动 Hive adapter）。
class LibraryConfig {
  LibraryConfig._();

  static DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  static bool get enabled => _db?.getLibraryEnabled() ?? false;

  static Future<void> setEnabled(bool value) async {
    await _db?.setLibraryEnabled(value);
  }

  static String get token => _db?.getLibraryToken() ?? '';

  static Future<void> setToken(String value) async {
    await _db?.setLibraryToken(sanitizeToken(value));
    await _db?.setLibraryEnabled(true); // 存进 token 就是"要用它"
  }

  /// 把粘贴/注入进来的 token 洗干净。
  ///
  /// 从浏览器复制时很容易带上 `token=`、`authorization:`、`bearer ` 前缀，
  /// 或者粘成好几行 —— 带着这些发给接口就是"您尚未登录"（真机踩过）。
  static String sanitizeToken(String raw) {
    var text = raw.trim();
    text = text.replaceFirst(
        RegExp(r'^(token|authorization)\s*[:=]\s*', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'^bearer\s+', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'\s'), '');
    // 复制时带上引号的也一起去掉
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1);
    }
    return text;
  }

  static Future<void> clearToken() async {
    await _db?.setLibraryToken('');
  }

  static String get lastName => _db?.getLibraryLastName() ?? '';

  static Future<void> setLastName(String value) async {
    await _db?.setLibraryLastName(value);
  }

  static int get lastCount => _db?.getLibraryLastCount() ?? 0;

  static Future<void> setLastCount(int value) async {
    await _db?.setLibraryLastCount(value);
  }

  static String get lastResult => _db?.getLibraryLastResult() ?? '';

  static Future<void> setLastResult(String value) async {
    await _db?.setLibraryLastResult(value);
  }

  /// 打码显示（设置页用；绝不整串显示 token）
  static String get maskedToken {
    final value = token;
    if (value.isEmpty) return '（还没填）';
    if (value.length <= 8) return '…';
    return value.substring(0, 4) + '……' + value.substring(value.length - 4);
  }

  /// 从 WebView 注入 JS 的**返回值**里抠出 token。
  ///
  /// runJavaScriptReturningResult 对 JS 字符串会带回**引号**（还可能转义），
  /// 拿不到时返回的是字符串 "null"/"" —— 这些都要当成"没有"。
  /// 纯逻辑，单测钉着。
  static String tokenFromJavaScript(Object? raw) {
    if (raw == null) return '';
    var text = raw.toString().trim();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1);
    }
    text = text.replaceAll(r'"', '"').replaceAll(r'\', r'').trim();
    if (text == 'null' || text == 'undefined' || text == '{}') return '';
    return text;
  }
}
