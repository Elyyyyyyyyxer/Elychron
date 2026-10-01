import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/http/pta_spider.dart';
import 'package:celechron/mod/pta_homework.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/cupertino.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// ===== 用内置浏览器登录 PTA，自动把 PTASession 取回来（2026-10-01）=====
///
/// 为什么需要它：PTA 的密码登录接口要过**腾讯验证码**（实测带上完整浏览器头、
/// 不带验证码票据，服务端直接 406），所以"填一次就永久"只能靠：让用户在我们
/// 自己的 WebView 里**正常登录一次**（验证码、微信扫码都行），再从 WebView 的
/// cookie 里把 PTASession 取出来。
///
/// 一个关键事实（动手前先核对过）：PTASession 是 **HttpOnly**，JS 的
/// document.cookie 读不到它。所以这里走的是**平台 cookie 接口**：
/// webview_flutter 的 WebViewCookieManager.getCookies（安卓底层就是
/// CookieManager.getCookie），它能读到 HttpOnly ✓。
///
/// 清空**内置浏览器自己的** cookie 库（安卓 / iOS）。
///
/// 为什么需要它：WebView 有它自己的一份 cookie，和 App 里存的那份是**两回事**。
/// 用户点「清除」时如果只清 App 那份，下次打开登录页 WebView 依然是登录状态
/// （用户实测：「我手动删掉之后进入浏览器还是直接通过，这对调试不太方便」）。
Future<void> clearPtaWebViewCookies() async {
  if (!PlatformFeatures.hasWebViewLogin) return;
  try {
    await WebViewCookieManager().clearCookies();
  } on Object {
    // 清不掉就算了：只影响"干净登录"，不影响别的功能
  }
}

/// 只支持安卓 / iOS：webview_flutter 没有 Windows 实现，桌面端继续用"粘贴"。
class PtaLoginPage extends StatefulWidget {
  const PtaLoginPage({super.key});

  @override
  State<PtaLoginPage> createState() => _PtaLoginPageState();
}

class _PtaLoginPageState extends State<PtaLoginPage> {
  static const String _loginUrl = 'https://pintia.cn/auth/login';

  WebViewController? _webView;
  bool _harvesting = false;
  String _status = '在下面登录 PTA；登录成功后会自动把登录信息存下来';

  @override
  void initState() {
    super.initState();
    // 桌面端不该走到这里（入口按 hasWebViewLogin 隐藏），防御性返回
    if (!PlatformFeatures.hasWebViewLogin) return;
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 用不带 wv 标记的 UA：有些站点会对"应用内浏览器"另眼相看
      ..setUserAgent('Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (String url) => _harvest(),
        onWebResourceError: (WebResourceError error) {
          if (!mounted) return;
          setState(() => _status = '页面加载失败：' + error.description);
        },
      ));
    _seedAndLoad();
  }

  /// 进页面先把**已经存着的** cookie 播进 WebView 的 cookie 库，再打开登录页：
  /// - 它还有效 → 一进去就能认出来（用户什么都不用做，页面自己就关了）；
  /// - 它过期了 → PTA 还是显示登录页，用户正常登录一次，新 cookie 会覆盖它。
  Future<void> _seedAndLoad() async {
    final controller = _webView;
    if (controller == null) return;
    final saved = PtaHomework.cookie;
    if (saved.isEmpty) {
      // App 里本来就没有登录信息 → 内置浏览器也必须从"未登录"开始。
      // 不这么做的话，上一次登录留在 WebView cookie 库里的会话会让人
      // 一进来就"自动通过"，既容易误会也没法调试。
      await clearPtaWebViewCookies();
    } else {
      try {
        await WebViewCookieManager().setCookie(WebViewCookie(
          name: 'PTASession',
          value: saved,
          domain: 'pintia.cn',
          path: '/',
        ));
      } on Object {
        // 播不进去就算了，用户手动登录一样能拿到新 cookie
      }
    }
    await controller.loadRequest(Uri.parse(_loginUrl));
  }

  /// 去 WebView 的 cookie 里找 PTASession
  Future<void> _harvest({bool manual = false}) async {
    if (_harvesting || _webView == null) return;
    _harvesting = true;
    try {
      final cookies = await WebViewCookieManager()
          .getCookies(domain: Uri.parse('https://pintia.cn'));
      String? session;
      for (final cookie in cookies) {
        if (cookie.name == 'PTASession' && cookie.value.isNotEmpty) {
          session = cookie.value;
        }
      }
      if (session == null) {
        DiagnosticLogService.instance.record(
          module: 'PTA',
          operation: 'webViewLogin',
          message: 'WebView 里还没看到 PTASession（读到 ' +
              cookies.length.toString() +
              ' 条 cookie）',
        );
        if (manual && mounted) {
          setState(() => _status = '还没登录成功 —— 先在下面登录，再点右上角「完成」');
        }
        return;
      }

      // ★ 关键：**先验再存**。
      //
      // PTA 的登录页自己也会下发一个**匿名**的 PTASession。不先验就存，
      // 会把用户本来能用的那份覆盖掉 —— 2026-10-01 真机踩过：读完 cookie、
      // 存下去、再验，才发现它是匿名的，而好的那份已经没了（界面就会显示
      // 「PTA 登录已过期」，用户一脸问号）。
      String nickname = '';
      final spider = PtaSpider(cookie: session);
      try {
        nickname = await spider.whoAmI();
      } on Object catch (error) {
        DiagnosticLogService.instance.record(
          module: 'PTA',
          operation: 'webViewLogin',
          message: 'WebView 里读到的 PTASession 还不可用（多半是"还没登录"）：' +
              error.toString(),
        );
        if (manual && mounted) {
          setState(() => _status = '还没登录成功 —— 先在下面登录，再点右上角「完成」');
        }
        return;
      } finally {
        spider.close();
      }
      if (nickname.isEmpty) {
        if (manual && mounted) {
          setState(() => _status = '还没登录成功 —— 先在下面登录，再点右上角「完成」');
        }
        return;
      }

      await PtaHomework.setCookie(session);
      DiagnosticLogService.instance.record(
        module: 'PTA',
        operation: 'webViewLogin',
        message: '从 WebView 验到有效登录（长度 ' +
            session.length.toString() +
            '），已保存',
      );
      if (!mounted) return;
      Navigator.of(context).pop('连接成功：' + nickname);
    } on Object catch (error) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: 'PTA',
        operation: 'webViewLogin',
        message: '读 cookie 失败：' + error.toString(),
      );
      if (mounted) setState(() => _status = '读取登录状态失败：' + error.toString());
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
        middle: const Text('登录 PTA'),
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
                    child: Text('桌面端没有内置浏览器，请回上一页用「粘贴 PTASession」。'),
                  )
                : WebViewWidget(controller: controller),
          ),
        ],
      ),
    );
  }
}
