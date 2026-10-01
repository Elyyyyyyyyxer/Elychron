import 'dart:async';
import 'dart:convert';

import 'package:celechron/http/library_spider.dart';
import 'package:celechron/mod/library_config.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// ===== 图书馆预约的"常驻网页会话"（2026-10-01）=====
///
/// **为什么必须是它**：这站是单设备登录，而且凭据只在那个页面里成立 ——
/// 实测在 Dart 侧另起 HttpClient 带 token 去请求会被判"您尚未登录"
/// （页面里明明显示着"当前预约"）。所以数据一律走"页面内同源 fetch"：
/// cookie、会话、它自己的 sessionStorage.token 全都自动带上，服务端看到的是
/// "页面自己在请求"，不是"另一台设备"。
///
/// 一个隐藏的 WebView 常驻在这里；App 启动时静默加载一次首页，
/// 之后所有读取（预约、状态）都从它的页面里发。
class LibraryWebSession {
  LibraryWebSession._();

  static final LibraryWebSession instance = LibraryWebSession._();

  static const String homeUrl = 'https://booking.lib.zju.edu.cn/h5/';
  static const String _ua = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
  static const Duration _loadTimeout = Duration(seconds: 20);
  static const Duration _jsTimeout = Duration(seconds: 10);

  WebViewController? _controller;
  Completer<void>? _loading;

  /// 桌面端没有 webview_flutter，硬构造会抛 —— 一律先问这张表
  bool get available => PlatformFeatures.hasWebViewLogin;

  bool get hasController => _controller != null;

  /// 登录页登录成功后把它的 controller 交接进来（省掉一次重复加载）
  void adopt(WebViewController controller) {
    _controller = controller;
    _loading = null;
  }

  /// 用户点「清除登录信息」时调
  void reset() {
    _controller = null;
    _loading = null;
  }

  /// 没有就建一个并等首页加载完；已经有就直接用
  Future<bool> ensureReady() async {
    if (!available) return false;
    final existing = _controller;
    if (existing != null) {
      final pending = _loading;
      if (pending == null) return true;
      try {
        await pending.future.timeout(_loadTimeout);
      } on Object {
        // 超时也可能已经加载完（onPageFinished 没来而已），交给调用方去试
      }
      return _controller != null;
    }

    final completer = Completer<void>();
    _loading = completer;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_ua)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (String url) {
          if (!completer.isCompleted) completer.complete();
        },
        onWebResourceError: (WebResourceError error) {
          libraryTrace('图书馆会话：页面报错 ' + error.description);
          if (!completer.isCompleted) completer.complete();
        },
      ))
      ..loadRequest(Uri.parse(homeUrl));
    _controller = controller;
    try {
      await completer.future.timeout(_loadTimeout);
      libraryTrace('图书馆会话：首页已就绪');
    } on Object {
      libraryTrace('图书馆会话：等首页超时（仍然继续尝试）');
    }
    return _controller != null;
  }

  /// 在页面里发一个 POST，把响应正文原样带回来。
  ///
  /// code==10001 直接抛 [LibraryAuthException]，并**带上服务端原话**
  /// （比如「请注意,您的账号在其他设备登录！」）—— 用户看到这句才知道该重登。
  Future<String> postJson(String path, [Map<String, dynamic>? body]) async {
    if (!available) {
      throw LibraryAuthException('图书馆预约：桌面端没有内置浏览器');
    }
    final ready = await ensureReady();
    final controller = _controller;
    if (!ready || controller == null) {
      throw LibraryAuthException('图书馆预约：内置浏览器没准备好');
    }

    // 结果写进 window.__ely 再轮询：不依赖各版本对 Promise 的支持差异（稳）。
    // body 用**双重 jsonEncode** 塞进去，任意 JSON 都能变成合法的 JS 字符串字面量。
    final payload = jsonEncode(jsonEncode(body ?? const <String, dynamic>{}));
    final js = "(function(){window.__ely='PENDING';"
        "fetch('" + path + "',{method:'POST',credentials:'include',"
        "headers:{'Content-Type':'application/json;charset=UTF-8',"
        "'X-Requested-With':'XMLHttpRequest',"
        "'authorization':'bearer'+(window.sessionStorage.getItem('token')||'')},"
        "body:" + payload + "})"
        ".then(function(r){return r.text()})"
        ".then(function(t){window.__ely=t})"
        ".catch(function(e){window.__ely='ERR:'+e});return 'started';})()";
    await controller.runJavaScriptReturningResult(js).timeout(_jsTimeout);

    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final raw = await controller
          .runJavaScriptReturningResult('window.__ely || ""')
          .timeout(_jsTimeout);
      final text = LibraryConfig.tokenFromJavaScript(raw);
      if (text.isEmpty || text.startsWith('PENDING')) continue;
      if (text.startsWith('ERR:')) {
        throw LibraryAuthException('图书馆预约：页面内请求失败（' + text.substring(4) + '）');
      }
      _throwIfNotLoggedIn(path, text);
      return text;
    }
    throw LibraryAuthException('图书馆预约：页面内请求超时');
  }

  void _throwIfNotLoggedIn(String path, String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on Object {
      return;
    }
    if (decoded is! Map) return;
    if (decoded['code'] != 10001) return;
    final reason =
        (decoded['msg'] ?? decoded['message'] ?? '').toString().trim();
    libraryTrace('页面内 ' + path + ' 被判未登录：' + reason);
    throw LibraryAuthException(
        reason.isEmpty ? '图书馆预约：登录已失效' : '图书馆预约：' + reason);
  }

  /// 现在到底是不是登录态
  Future<bool> isLoggedIn() async {
    try {
      final body = await postJson('/api/Member/my');
      final decoded = jsonDecode(body);
      return decoded is Map && decoded['code'] == 1;
    } on Object {
      return false;
    }
  }
}
