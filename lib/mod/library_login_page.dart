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

  /// 从 WebView 里读 token（读不到就是还没登录）。
  ///
  /// 2026-10-01 真机踩的坑：注入 JS 一旦卡住，_harvesting 守卫会把之后所有点击
  /// **静默丢掉** —— 用户点「完成」什么反应都没有。所以这里：给 JS 调用加超时、
  /// 手动点击即使"没读到"也一定要有反馈、并且把长度写进诊断日志。
  Future<void> _harvest({bool manual = false}) async {
    final controller = _webView;
    if (controller == null) return;
    if (_harvesting) {
      if (manual && mounted) setState(() => _status = '正在读取登录状态，请稍等一下再点');
      return;
    }
    _harvesting = true;
    try {
      // ① 先把"里面到底存了什么"记进日志：键名 + 值长度。
      //    （这样万一取不到 token，日志能直接告诉我它藏在哪个键下，不用瞎猜。）
      try {
        final probe = await controller
            .runJavaScriptReturningResult(
                'JSON.stringify({s:Object.keys(window.sessionStorage).map(function(k){return k+":"+String(window.sessionStorage.getItem(k)||"").length}),l:Object.keys(window.localStorage).map(function(k){return k+":"+String(window.localStorage.getItem(k)||"").length})})')
            .timeout(const Duration(seconds: 8));
        DiagnosticLogService.instance.record(
          module: '图书馆预约',
          operation: 'webViewStorage',
          message: probe.toString().replaceAll('"', ''),
        );
      } on Object {
        // 照不出来就算了，不影响后面取 token
      }
      // ② sessionStorage 是它的前端用的地方；localStorage 一并兜住（版本差异）
      final raw = await controller
          .runJavaScriptReturningResult(
              'window.sessionStorage.getItem("token") || window.localStorage.getItem("token") || ""')
          .timeout(const Duration(seconds: 8));
      final token = LibraryConfig.tokenFromJavaScript(raw);
      DiagnosticLogService.instance.record(
        module: '图书馆预约',
        operation: 'webViewLogin',
        message: '注入 JS 取到 token 长度=' + token.length.toString(),
      );
      if (token.isEmpty) {
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
      if (mounted) setState(() => _status = '没成功：' + error.toString());
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
