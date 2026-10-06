import 'dart:convert';
import 'dart:io';

import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/http/library_spider.dart';
import 'package:celechron/mod/library_config.dart';
import 'package:celechron/mod/library_web_session.dart';
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
        onNavigationRequest: (NavigationRequest request) async {
          final uri = Uri.tryParse(request.url);
          final secure =
              uri == null ? null : LibraryWebSession.secureCasRedirect(uri);
          if (secure != null && _webView != null) {
            await _webView!.loadRequest(secure);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (WebResourceError error) {
          if (!mounted) return;
          setState(() => _status = '页面加载失败：' + error.description);
        },
      ))
      // Establish the booking session before entering CAS on iOS.
      ..loadRequest(
          Uri.parse(Platform.isIOS ? LibraryWebSession.casEntryUrl : _homeUrl));
    // 交接给常驻会话：这个页面就是"那把钥匙"，之后所有读取都用它
    // （不能另起 HttpClient —— 服务端会当成另一台设备，见 library_web_session 的注释）
    LibraryWebSession.instance.adopt(_webView!);
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
      final current = Uri.tryParse(await controller.currentUrl() ?? '');
      if (current?.host != 'booking.lib.zju.edu.cn') {
        if (mounted) setState(() => _status = '请在下面完成统一身份认证登录');
        return;
      }
      // 数据**在页面里取**（关键改动，2026-10-01）：
      //
      // 实测：WebView 里页面自己显示着"当前预约"，而我们在 Dart 侧另起一个
      // HttpClient 带 token 去请求，却被判"您尚未登录" —— 说明凭据/会话只在
      // **这个页面**里成立，外面那一路在服务端看来就是"另一台设备"
      // （这站还是单设备登录）。
      // 所以：同源 fetch 交给页面自己发，cookie/会话/它的 token 全都自动带上。
      final me = await LibraryWebSession.instance.postJson('/api/Member/my');
      final decodedMe = jsonDecode(me);
      final code = decodedMe is Map ? decodedMe['code'] : null;
      libraryTrace('页面内 /api/Member/my → ' +
          (me.length > 160 ? me.substring(0, 160) : me));
      if (code != 1) {
        final reason = decodedMe is Map
            ? (decodedMe['msg'] ?? decodedMe['message'] ?? '').toString()
            : '';
        if (mounted) {
          setState(
              () => _status = '还没登录成功' + (reason.isEmpty ? '' : '：' + reason));
        }
        return;
      }
      final name = (decodedMe is Map && decodedMe['data'] is Map)
          ? (decodedMe['data']['name']?.toString() ?? '')
          : '';
      // 顺手读一次"我的预约"，用现成的防御式解析数一下
      var count = 0;
      try {
        count = LibrarySpider.reservationsFrom(jsonDecode(
                await LibraryWebSession.instance
                    .postJson('/api/Member/seminar')))
            .length;
      } on Object {
        // 数不出来不影响"登录成功"这个结论
      }
      await LibraryConfig.setEnabled(true);
      LibraryWebSession.instance.adoptToken(LibraryConfig.tokenFromJavaScript(
          await LibraryWebSession.instance.runTokenProbe()));
      await LibraryConfig.setLastCount(count);
      await LibraryConfig.setLastResult('页面内登录成功' +
          (name.isEmpty ? '' : '：' + name) +
          (count > 0 ? '，共 ' + count.toString() + ' 条预约' : ''));
      if (!mounted) return;
      Navigator.of(context).pop('连接成功' +
          (name.isEmpty ? '' : '：' + name) +
          (count > 0 ? '，共 ' + count.toString() + ' 条预约' : ''));
      return;
    } on Object catch (error) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: '图书馆预约',
        operation: 'webViewLogin',
        message: '读/验 token 失败：' + error.toString(),
      );
      libraryTrace('WebView 取值/验证失败：' + error.toString());
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
