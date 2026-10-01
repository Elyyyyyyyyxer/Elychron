import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/http/library_spider.dart';
import 'package:celechron/mod/library_config.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// ===== 用内置浏览器登录图书馆预约，自动把 token 取回来（2026-10-01）=====
///
/// 为什么这么取：这站点的登录态是 **sessionStorage 里的 token**，不是 cookie
/// （实测：只带 PHPSESSID 会被判"您尚未登录"；带 `authorization: bearer<token>` 才认）。
/// 而 sessionStorage 用**注入 JS** 能直接读到（不像 HttpOnly cookie 那样读不到），
/// 所以：打开它的 h5 → 用户正常登录（CAS/微信都行）→ 注入 JS 读 token → **先验再存**。
///
/// "先验再存"是 PTA 那次的教训：站点在登录前也会下发一个**匿名**凭据，
/// 不验证就存会把本来能用的那份覆盖掉。
/// 清空内置浏览器自己的 cookie（和 PTA 那边同一个道理：WebView 有独立的一份）
Future<void> clearLibraryWebViewCookies() async {
  if (!PlatformFeatures.hasWebViewLogin) return;
  try {
    await WebViewCookieManager().clearCookies();
  } on Object {
    // 清不掉就算了
  }
}

class LibraryLoginPage extends StatefulWidget {
  const LibraryLoginPage({super.key});

  @override
  State<LibraryLoginPage> createState() => _LibraryLoginPageState();
}

class _LibraryLoginPageState extends State<LibraryLoginPage> {
  static const String _homeUrl = 'https://booking.lib.zju.edu.cn/h5/';

  WebViewController? _webView;
  bool _harvesting = false;
  String _status = '在下面登录；登录成功后会自动把登录信息存下来';

  @override
  void initState() {
    super.initState();
    if (!PlatformFeatures.hasWebViewLogin) return;
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (String url) => _harvest(),
        onWebResourceError: (WebResourceError error) {
          if (!mounted) return;
          setState(() => _status = '页面加载失败：' + error.description);
        },
      ))
      ..loadRequest(Uri.parse(_homeUrl));
  }

  /// 从 WebView 的 sessionStorage 里读 token（读不到就是还没登录）
  Future<void> _harvest({bool manual = false}) async {
    final controller = _webView;
    if (_harvesting || controller == null) return;
    _harvesting = true;
    try {
      final raw = await controller.runJavaScriptReturningResult(
          'window.sessionStorage.getItem("token") || ""');
      final token = LibraryConfig.tokenFromJavaScript(raw);
      if (token.isEmpty) {
        DiagnosticLogService.instance.record(
          module: '图书馆预约',
          operation: 'webViewLogin',
          message: 'WebView 里还没看到 token',
        );
        if (manual && mounted) {
          setState(() => _status = '还没登录成功 —— 先在下面登录，再点右上角「完成」');
        }
        return;
      }
      // ★ 先验再存
      final spider = LibrarySpider.withToken(token);
      try {
        final name = await spider.verify();
        await LibraryConfig.setToken(token);
        DiagnosticLogService.instance.record(
          module: '图书馆预约',
          operation: 'webViewLogin',
          message: '从 WebView 验到有效 token，已保存（' + name.length.toString() + ' 字的名字）',
        );
        if (!mounted) return;
        Navigator.of(context).pop(name.isEmpty ? '连接成功' : '连接成功：' + name);
      } finally {
        spider.close();
      }
    } on Object catch (error) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: '图书馆预约',
        operation: 'webViewLogin',
        message: '读/验 token 失败：' + error.toString(),
      );
      if (manual && mounted) setState(() => _status = '还没登录成功或读了读不出来：' + error.toString());
    } finally {
      _harvesting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _webView;
    return CupertinoPageScaffold(
      backgroundColor: pageBackground(context),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('登录图书馆预约'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: controller == null ? null : () => _harvest(manual: true),
          child: const Text('完成'),
        ),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            color: AppAccent.soft(0.08),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_status, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: controller == null
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('桌面端没有内置浏览器，请回上一页用「粘贴 token」。'),
                  )
                : WebViewWidget(controller: controller),
          ),
        ],
      ),
    );
  }
}
