import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:celechron/http/library_spider.dart';
import 'package:celechron/http/zjuServices/zjuam.dart';
import 'package:celechron/mod/library_config.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:get/get.dart';
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

  /// CAS 入口：会 302 到 http://zjuam.zju.edu.cn/cas/login?service=...
  /// （明文 HTTP 已在 network_security_config 里对 zju.edu.cn 放开）
  static const String casEntryUrl = 'https://booking.lib.zju.edu.cn/api/cas/cas';

  /// 直接走 CAS 登录页（**HTTPS**，不走上面那个 HTTP 跳转）。
  ///
  /// 2026-10-01 真机对出来的：顺着 /api/cas/cas 的 302 过去会落到 **http://** 的登录页，
  /// 而 App 自己那份统一身份认证登录（ZjuAm）用的是 https。https 这边表单能提交、
  /// SSO cookie 也才会被带上；http 那边提交后 CAS 直接把你弹回登录页（连报错都没有）。
  static const String casLoginUrl = 'https://zjuam.zju.edu.cn/cas/login?service='
      'https%3A%2F%2Fbooking.lib.zju.edu.cn%2Fapi%2Fcas%2Fcas';

  static const String _ua = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
  static const Duration _loadTimeout = Duration(seconds: 20);
  static const Duration _jsTimeout = Duration(seconds: 10);

  /// 两次后台重登之间的最小间隔：重登失败时别把接口请求变成"每次登一次"。
  static const Duration _reloginCooldown = Duration(seconds: 45);

  /// ===== 开发验证开关（发布版默认关闭，这段是死代码会被摇掉）=====
  ///
  /// 真机上 CAS 往往还有会话，后台重登走的是"免填表"那条捷径，
  /// 看不出"自动填表并提交"到底对不对。用
  ///   flutter build apk --dart-define=ELY_FORCE_RELOGIN=true
  /// 构建时，第一次 ensureReady 会先清空内置浏览器 cookie，逼出填表那条路。
  static const bool _forceReloginForTest =
      bool.fromEnvironment('ELY_FORCE_RELOGIN');
  bool _forceReloginDone = false;

  /// 是否处在"强制后台重登"的验证模式（发布版恒为 false）
  bool get forceReloginForTest => _forceReloginForTest;

  WebViewController? _controller;
  Completer<void>? _loading;

  /// 页面自己恢复出来的 token（诊断用：能看出"新开一个 WebView 到底还能不能自动恢复登录"）
  String _token = '';

  /// 后台重登的并发闸门 + 冷却（同一时刻只登一次）
  bool _relogging = false;
  DateTime? _lastReloginAt;

  /// 最近一次后台重登失败的原因（人话；设置页可直接透出）
  String _lastAuthMessage = '';

  String get token => _token;

  String get lastAuthMessage => _lastAuthMessage;

  /// 桌面端没有 webview_flutter，硬构造会抛 —— 一律先问这张表
  bool get available => PlatformFeatures.hasWebViewLogin;

  bool get hasController => _controller != null;

  /// 登录页登录成功后把它的 controller 交接进来（省掉一次重复加载）
  void adopt(WebViewController controller) {
    _controller = controller;
    _loading = null;
  }

  /// 读一次当前页面里的 token（登录页交接 / 诊断用）
  Future<Object?> runTokenProbe() async {
    final controller = _controller;
    if (controller == null) return null;
    try {
      return await controller
          .runJavaScriptReturningResult(
              'window.sessionStorage.getItem("token") || ""')
          .timeout(_jsTimeout);
    } on Object {
      return null;
    }
  }

  /// 登录页验证成功后把它的 token 也交接过来（诊断/日志用）
  void adoptToken(String token) {
    _token = token;
  }

  /// 用户点「清除登录信息」时调
  void reset() {
    _controller = null;
    _loading = null;
  }

  /// 没有就建一个并等首页加载完；已经有就直接用
  Future<bool> ensureReady() async {
    if (!available) return false;
    if (_forceReloginForTest && !_forceReloginDone) {
      _forceReloginDone = true;
      _controller = null;
      _loading = null;
      try {
        await WebViewCookieManager().clearCookies();
        libraryTrace('（验证模式）已清空内置浏览器 cookie，接下来必须走填表重登');
      } on Object {
        // 清不掉就照常走
      }
    }
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
        onNavigationRequest: (NavigationRequest request) {
          // 只记 host + path：**丢掉 query**，因为回调地址里带着一次性的 CAS ticket
          // （凭据绝不进日志，见 AGENTS.md）。
          final uri = Uri.tryParse(request.url);
          final safe = uri == null ? '(无法解析)' : uri.host + uri.path;
          libraryTrace('图书馆会话：导航 → ' + safe);
          return NavigationDecision.navigate;
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
    // ★ 必须等页面**自己把登录态恢复出来**再取数据。
    //
    // 2026-10-01 真机踩的：这站的登录态存在 sessionStorage 里，而
    // **每新建一个 WebView，sessionStorage 都是空的** —— 上一次登录留在那里的
    // token 不会跟过来。页面刚 onPageFinished 时它的 JS 还没跑完，
    // 我们立刻发请求就会被判"您尚未登录"（实测日志就是这么写的）。
    // 所以这里等一下：页面如果还能靠 cookie 恢复登录，它自己会把 token 写回去。
    _token = await _waitForToken(const Duration(seconds: 12));
    libraryTrace('图书馆会话：等到的 token 长度=' + _token.length.toString());
    if (_token.isEmpty) {
      // 页面自己恢复不出登录态（被别的设备顶掉 / sessionStorage 是空的）
      // → 在**同一个隐藏 WebView**里静默走一遍 CAS 登录，用户什么都不用做。
      // 这就是用户要的"查看的优越性"：只要在教务登录过一次，这里每次刷新都能自己重登。
      await silentRelogin();
    }
    return _controller != null;
  }

  /// 教务里那份账号密码（**只在内存里用**，不落任何新存储、不打日志）。
  ///
  /// 用户拍板："只要 Elychron 登录过一次，之后每次刷新都在后台自动重登。"
  /// 凭据本来就是教务在用的同一份（见 Scholar.username / password），
  /// 这里只是借来在同源 WebView 里过一遍 CAS。
  ({String username, String password})? _credentials() {
    try {
      if (!Get.isRegistered<Rx<Scholar>>(tag: 'scholar')) return null;
      final scholar = Get.find<Rx<Scholar>>(tag: 'scholar').value;
      final username = (scholar.username ?? '').trim();
      final password = scholar.password ?? '';
      if (username.isEmpty || password.isEmpty) return null;
      return (username: username, password: password);
    } on Object {
      return null;
    }
  }

  /// 后台静默重登：同一个隐藏 WebView 里打开 CAS → 注入账号密码 → 提交 → 等 token。
  ///
  /// 全程不弹任何界面、失败只写日志。返回是否真的重登成功。
  Future<bool> silentRelogin({bool force = false}) async {
    if (!available) return false;
    final controller = _controller;
    if (controller == null) return false;
    if (_relogging) {
      libraryTrace('自动重登：已有一次重登在进行，跳过');
      return false;
    }
    final last = _lastReloginAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _reloginCooldown) {
      libraryTrace('自动重登：冷却中（' +
          DateTime.now().difference(last).inSeconds.toString() +
          ' 秒前刚试过），跳过');
      return false;
    }
    final credentials = _credentials();
    if (credentials == null) {
      _lastAuthMessage = '图书馆预约：没有可用的统一身份认证账号密码，无法后台重登';
      libraryTrace('自动重登：手上没有教务账号密码，跳过（不弹任何界面）');
      return false;
    }
    _relogging = true;
    _lastReloginAt = DateTime.now();
    try {
      libraryTrace('自动重登：打开 CAS 登录页（' + casLoginUrl + '）');
      await controller.loadRequest(Uri.parse(casLoginUrl));
      // 两种可能：CAS 里 SSO 还有效 → 直接跳回业务站并出 token（不用填表）；
      // 否则停在登录页 → 等 #username/#password 出现再注入。
      final stage = await _waitForLoginStage(const Duration(seconds: 12));
      if (stage.stage == 'token') {
        _token = stage.token;
        _lastAuthMessage = '';
        libraryTrace('自动重登成功（CAS 仍有会话，免填表）：token 长度=' +
            stage.token.length.toString());
        return true;
      }
      // ★ 首选：Dart 侧申请一张一次性 ticket，交给内置 WebView 去访问回调。
      //   这和用户在浏览器里点登录后发生的事完全一致，2026-10-01 真机验证通过。
      if (await _reloginWithTicket(credentials.username, credentials.password)) {
        return true;
      }
      // 备选：在 WebView 里注入账号密码、提交它自己的登录表单。
      // （用户点名要的做法；本机 CAS 不认这种程序化提交，留作别的部署的备选。）
      libraryTrace('自动重登：ticket 兜底没成，改用注入填表');
      await controller.loadRequest(Uri.parse(casLoginUrl));
      final formStage = await _waitForLoginStage(const Duration(seconds: 15));
      if (formStage.stage != 'form') {
        _lastAuthMessage = '图书馆预约：自动重登没能打开统一身份认证页面';
        libraryTrace('自动重登：没等到登录表单，当前地址=' + await _currentUrl());
        return false;
      }
      // 只打长度，绝不打内容（凭据不进任何日志）。
      libraryTrace('自动重登：学号长度=' + credentials.username.length.toString() +
          ' 密码长度=' + credentials.password.length.toString());
      final injected =
          await _injectCredentials(credentials.username, credentials.password);
      libraryTrace('自动重登：表单注入结果=' + injected);
      libraryTrace('自动重登：注入后探针=' + await _injectProbe());
      if (injected == 'captcha') {
        _lastAuthMessage = '图书馆预约：统一身份认证要求输入验证码，后台重登需要你手动登录一次';
        return false;
      }
      final submitted = injected == 'submitted' ||
          injected.startsWith('called') ||
          injected.startsWith('clicked');
      if (!submitted) {
        _lastAuthMessage = '图书馆预约：自动重登没能提交登录表单（' + injected + '）';
        libraryTrace('自动重登：没能提交表单，注入结果=' + injected);
        return false;
      }
      libraryTrace('自动重登：表单已提交（' + injected + '），等 ticket 回调后的 token');
      // 先等 ticket 回调那一跳，等不到就回首页让它的 JS 把 token 写出来。
      final token = await _waitForToken(const Duration(seconds: 20));
      if (token.isEmpty) {
        _lastAuthMessage = '图书馆预约：自动重登后仍没恢复登录';
        final casMessage = await _readElementText('errormsg');
        libraryTrace('自动重登：提交后仍没有 token，当前地址=' + await _currentUrl() +
            (casMessage.isEmpty ? '' : '，CAS 提示=' + casMessage));
        libraryTrace('自动重登：登录页正文=' + await _readBodyText());
        return false;
      }
      _token = token;
      _lastAuthMessage = '';
      libraryTrace('自动重登成功：token 长度=' + token.length.toString());
      return true;
    } on Object catch (error) {
      _lastAuthMessage = '图书馆预约：自动重登失败（' + error.toString() + '）';
      libraryTrace('自动重登失败：' + error.toString());
      return false;
    } finally {
      _relogging = false;
    }
  }

  /// 兜底（真机上真正管用的那条）：用 App 自己那套统一身份认证登录，**在 Dart 侧**
  /// 申请一张一次性的 CAS ticket，把带 ticket 的回调地址交给**内置 WebView 去访问**。
  ///
  /// 为什么不自己在 WebView 里填表：实测在隐藏 WebView 里提交 CAS 表单，服务端要么把
  /// 你弹回登录页、要么连跳转都不发生（页面正文仍是一个干净的登录页），怎么都对不上。
  /// 而 "ZjuAm 登录拿 SSO → getServiceCallback 拿 ticket → WebView 访问回调" 这条路
  /// 和用户在浏览器里点登录后发生的事**完全一致**：ticket 由 WebView 这个会话消费，
  /// phpCAS 建起业务站自己的会话，首页 JS 再把 token 写回来。
  Future<bool> _reloginWithTicket(String username, String password) async {
    final controller = _controller;
    if (controller == null) return false;
    final client = HttpClient();
    try {
      // ① 先让 WebView 在业务站拿到自己的 PHPSESSID（phpCAS 校验 ticket 时要带上它）
      await controller.loadRequest(Uri.parse(homeUrl));
      await Future<void>.delayed(const Duration(seconds: 2));
      // ② Dart 侧完成统一身份认证，拿 SSO cookie
      final sso = await ZjuAm.getSsoCookie(client, username, password);
      if (sso == null || sso.value.isEmpty) {
        libraryTrace('自动重登（ticket 兜底）：没拿到统一身份认证 cookie');
        return false;
      }
      // ③ 申请一次性 ticket（只读 Location，**不消费**它），交给 WebView 去访问
      final callback = await ZjuAm.getServiceCallback(
        client,
        sso,
        Uri.parse(LibrarySpider.casServiceUrl),
        context: '图书馆预约后台重登',
      );
      libraryTrace('自动重登（ticket 兜底）：拿到 ticket，交给内置浏览器消费');
      await controller.loadRequest(callback);
      var token = await _waitForToken(const Duration(seconds: 25));
      if (token.isEmpty) {
        // 回调页可能停在半路，回首页让它的 JS 把 token 写出来
        await controller.loadRequest(Uri.parse(homeUrl));
        token = await _waitForToken(const Duration(seconds: 15));
      }
      if (token.isEmpty) {
        libraryTrace('自动重登（ticket 兜底）仍没等到 token，当前地址=' + await _currentUrl());
        return false;
      }
      _token = token;
      _lastAuthMessage = '';
      libraryTrace('自动重登成功（ticket 兜底）：token 长度=' + token.length.toString());
      return true;
    } on Object catch (error) {
      libraryTrace('自动重登（ticket 兜底）失败：' + error.toString());
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// 读整页正文（截断）——CAS 的报错不一定挂在 #errormsg 上，看正文最实在。
  Future<String> _readBodyText() async {
    final controller = _controller;
    if (controller == null) return '';
    try {
      final raw = await controller
          .runJavaScriptReturningResult(
              "(function(){var b=document.body;var t=b?(b.innerText||b.textContent||''):'';t=t.replace(/[\\r\\n\\t]+/g,' ').trim();return t.length>400?t.substring(0,400):t;})()")
          .timeout(_jsTimeout);
      return LibraryConfig.tokenFromJavaScript(raw);
    } on Object {
      return '';
    }
  }

  /// 注入后立刻回读：值有没有落进去、有没有重复 id、验证码是否出现、页面上有没有报错。
  Future<String> _injectProbe() async {
    final controller = _controller;
    if (controller == null) return 'no-controller';
    const js = "(function(){var u=document.getElementById('username');"
        "var p=document.getElementById('password');"
        "var k=document.getElementById('kaptcha');"
        "var e=document.getElementById('errormsg');"
        "return JSON.stringify({u:(u?u.value.length:-1),p:(p?p.value.length:-1),"
        "uc:document.querySelectorAll('#username').length,"
        "pc:document.querySelectorAll('#password').length,"
        "k:(k?getComputedStyle(k).display:'absent'),"
        "cf:(typeof checkForm),"
        "dlBound:(function(){try{var d=document.getElementById('dl');if(!window.jQuery||!d)return 'no-jq';var v=window.jQuery._data(d,'events');return (v&&v.click)?'yes':'no';}catch(e){return 'err';}})(),"
        "m:(function(){var x=document.getElementById('msg');return x?(x.innerText||''):'';})(),"
        "err:(e?(e.innerText||''):'')});})()";
    try {
      final raw = await controller
          .runJavaScriptReturningResult(js)
          .timeout(_jsTimeout);
      return LibraryConfig.tokenFromJavaScript(raw);
    } on Object catch (error) {
      return 'probe-error:' + error.toString();
    }
  }

  /// 读页面上某个元素的文字（CAS 报错时用来把原因带进日志；截断到 120 字）。
  Future<String> _readElementText(String id) async {
    final controller = _controller;
    if (controller == null) return '';
    try {
      final raw = await controller
          .runJavaScriptReturningResult(
              "(function(){var e=document.getElementById('" + id + "');return e?(e.innerText||e.textContent||''):'';})()")
          .timeout(_jsTimeout);
      final text = LibraryConfig.tokenFromJavaScript(raw);
      return text.length > 120 ? text.substring(0, 120) : text;
    } on Object {
      return '';
    }
  }

  Future<String> _currentUrl() async {
    try {
      return await _controller?.currentUrl() ?? '';
    } on Object {
      return '';
    }
  }

  /// 轮询 CAS 页面：要么等 token 自己出来（SSO 还有效），要么等登录表单出现。
  ///
  /// 返回 stage='token'（带 token）/ 'form' / 'timeout'。
  Future<({String stage, String token})> _waitForLoginStage(
      Duration timeout) async {
    final controller = _controller;
    if (controller == null) return (stage: 'timeout', token: '');
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final raw = await controller
            .runJavaScriptReturningResult(
                "(function(){return (document.readyState==='complete'&&document.getElementById('username')&&document.getElementById('password'))?'yes':'no';})()")
            .timeout(_jsTimeout);
        if (LibraryConfig.tokenFromJavaScript(raw) == 'yes') {
          return (stage: 'form', token: '');
        }
      } on Object {
        // 页面还在导航，接着等
      }
      try {
        final raw = await controller
            .runJavaScriptReturningResult(
                'window.sessionStorage.getItem("token") || window.localStorage.getItem("token") || ""')
            .timeout(_jsTimeout);
        final token = LibraryConfig.tokenFromJavaScript(raw);
        if (token.isNotEmpty) return (stage: 'token', token: token);
      } on Object {
        // 同上
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return (stage: 'timeout', token: '');
  }

  /// 在 CAS 登录页里填表并提交。
  ///
  /// 关键：**不自己拼表单**，只把值填进 #username / #password 再点它自己的登录按钮。
  /// 页面自己的登录按钮（#dl）绑的是 checkForm()：先取 RSA 公钥、把密码**倒序**后加密
  /// 再提交。真机实测：直接点 #dl 或调 checkForm() 都可能「默默地什么都不发生」
  /// （它内部走 jQuery 异步 getJSON，失败时没有回调、页面纹丝不动，日志里也看不出）。
  /// 所以这里**用同样的算法自己走一遍**：同步 XHR 取公钥 + 页面自带的 RSAUtils 加密，
  /// 每一步都返回一个可读的结果，失败能定位到具体是哪一步。
  Future<String> _injectCredentials(String username, String password) async {
    final controller = _controller;
    if (controller == null) return 'noform';
    // jsonEncode 保证任意字符（引号 / 反斜杠 / Unicode）都变成合法 JS 字符串字面量
    final user = jsonEncode(username);
    final pass = jsonEncode(password);
    final js = "(function(){"
        "var u=document.getElementById('username');"
        "var p=document.getElementById('password');"
        "if(!u||!p)return 'noform';"
        // 页面要求验证码时不能瞎点：如实返回，让设置页显示"需要手动登录一次"
        "var k=document.getElementById('kaptcha');"
        "if(k&&window.getComputedStyle(k).display!=='none')return 'captcha';"
        "u.value=" + user + ";"
        "p.value=" + pass + ";"
        "var r=document.getElementById('rember');if(r)r.checked=true;"
        "var f=document.getElementById('fm1');"
        "if(!f)return 'noform';"
        // ===== 复刻页面 checkForm 的流程，但每一步都能报错 =====
        // 真机实测：点 #dl / 调 checkForm() 都可能"默默地什么都不发生"
        // （checkForm 内部走 jQuery 异步 getJSON，失败时没有回调、页面纹丝不动）。
        // 这里用同步 XHR 取公钥、用页面自带的 RSAUtils 加密，每一步都返回可读的原因。
        "var pk=null;"
        "try{var x=new XMLHttpRequest();x.open('GET','v2/getPubKey',false);x.send(null);"
        "pk=JSON.parse(x.responseText);}catch(e){return 'pubkey-fail:'+e;}"
        "if(!pk||!pk.modulus||!pk.exponent)return 'pubkey-empty';"
        "if(typeof RSAUtils==='undefined')return 'no-rsa';"
        "try{var key=new RSAUtils.getKeyPair(pk.exponent,'',pk.modulus);"
        "p.value=RSAUtils.encryptedString(key,p.value.split('').reverse().join(''));}"
        "catch(e){return 'encrypt-fail:'+e;}"
        "try{f.submit();}catch(e){return 'submit-fail:'+e;}"
        "return 'submitted';})()";
    final raw =
        await controller.runJavaScriptReturningResult(js).timeout(_jsTimeout);
    return LibraryConfig.tokenFromJavaScript(raw);
  }

  /// 轮询页面，等它自己把 sessionStorage.token 写回来（等不到就返回空）
  Future<String> _waitForToken(Duration timeout) async {
    final controller = _controller;
    if (controller == null) return '';
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final raw = await controller
            .runJavaScriptReturningResult(
                'window.sessionStorage.getItem("token") || window.localStorage.getItem("token") || ""')
            .timeout(_jsTimeout);
        final text = LibraryConfig.tokenFromJavaScript(raw);
        if (text.isNotEmpty) return text;
      } on Object {
        // 页面还没就绪，接着等
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return '';
  }

  /// 在页面里发一个 POST，把响应正文原样带回来。
  ///
  /// 被判未登录（code==10001）时**先静默重登一次再重试**：这正是用户要的
  /// "只要登录过一次，每次刷新都在后台自动重登"。重试还失败才抛
  /// [LibraryAuthException]，并带上服务端原话
  /// （比如「请注意,您的账号在其他设备登录！」）—— 用户看到这句才知道该做什么。
  Future<String> postJson(String path, [Map<String, dynamic>? body]) async {
    if (!available) {
      throw LibraryAuthException('图书馆预约：桌面端没有内置浏览器');
    }
    final ready = await ensureReady();
    if (!ready || _controller == null) {
      throw LibraryAuthException('图书馆预约：内置浏览器没准备好');
    }

    var text = await _fetchInPage(path, body);
    if (_isNotLoggedIn(text)) {
      libraryTrace('页面内 ' + path + ' 被判未登录 → 尝试后台静默重登');
      if (await silentRelogin()) {
        text = await _fetchInPage(path, body);
      }
    }
    _throwIfNotLoggedIn(path, text);
    return text;
  }

  /// 页面内的一次 fetch（不含重登逻辑）。
  Future<String> _fetchInPage(String path, Map<String, dynamic>? body) async {
    final controller = _controller;
    if (controller == null) {
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
      return text;
    }
    throw LibraryAuthException('图书馆预约：页面内请求超时');
  }

  /// 响应是不是"未登录"（服务端的 code=10001）
  bool _isNotLoggedIn(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map && decoded['code'] == 10001;
    } on Object {
      return false;
    }
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
