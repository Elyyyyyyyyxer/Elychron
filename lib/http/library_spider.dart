import 'dart:convert';
import 'dart:io';

import 'package:celechron/http/zjuServices/zjuam.dart';
import 'package:celechron/services/diagnostic_log_service.dart';

/// ===== 图书馆空间预约系统（2026-10-01）=====
///
/// 侦察结论见 docs/CAMPUS_SERVICES_PLAN.md 第四节。要点：
/// - 宿主 https://booking.lib.zju.edu.cn 校外**可达**（实测 200/302），
///   不像手机版图书馆（m.lib）那样只放校网；
/// - 登录走 CAS，service = https://booking.lib.zju.edu.cn/api/cas/cas；
/// - 复用 App 已有的 zjuam 能力：getSsoCookie → getServiceCallback →
///   **完整访问带 ticket 的回调**（只拿 Location 不消费回调是不会建立会话的，
///   样板见 zjuServices/sztz.dart）→ 后端（phpCAS）建立自己的 PHPSESSID 会话；
/// - 于是**不需要用户为此再填任何账号密码**：用的就是教务那套 ZJU 账号。
///
/// 接口全是 POST + JSON，路径 /api/...；未登录时后端返回
/// code=10001「您尚未登录」（实测），我们据此判定登录失效。
class LibraryAuthException implements Exception {
  LibraryAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一条公告（/api/index/notice 是免登录的，用来做连通性自检最合适）
class LibraryNotice {
  const LibraryNotice(this.id, this.title, this.createdAt);

  final String id;
  final String title;
  final String createdAt;
}

/// 一条我的预约（座位 / 研讨间 / 活动）。
///
/// ⚠️ 这里是**防御式解析**：线上真实的字段名要等一次真登录才能确认
/// （见 docs 第四节：「第一次实现时必须拿真数据对一遍字段名」）。
/// 所以常见键名都认，认不出就留空，绝不因为一个字段缺失整条丢掉。
class LibraryReservation {
  const LibraryReservation({
    required this.title,
    required this.place,
    required this.start,
    required this.end,
  });

  final String title;
  final String place;
  final DateTime? start;
  final DateTime? end;

  static LibraryReservation? fromJson(Map<String, dynamic> json) {
    String pick(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
      return '';
    }

    DateTime? pickTime(List<String> keys) {
      final raw = pick(keys);
      return raw.isEmpty ? null : DateTime.tryParse(raw);
    }

    final start = pickTime(<String>['start_time', 'startTime', 'start', 'begin_time', 'date_time']);
    final end = pickTime(<String>['end_time', 'endTime', 'end', 'finish_time']);
    final title = pick(<String>['title', 'name', 'room_name', 'seat_name', 'area_name', 'space_name', 'activity_name']);
    final place = pick(<String>['place', 'address', 'room', 'area', 'space', 'lib_name', 'location']);
    if (title.isEmpty && place.isEmpty && start == null && end == null) return null;
    return LibraryReservation(
      title: title.isEmpty ? '图书馆预约' : title,
      place: place,
      start: start,
      end: end,
    );
  }
}

/// 极简 cookie jar：dart:io 的 HttpClient **不会**帮你在请求之间记住 cookie，
/// 而 CAS 这条路必须同时带上两样东西：
///   · zjuam 的 SSO cookie（ZjuAm 自己负责加）；
///   · 预约系统的 PHPSESSID（第一次跳转时后端下发，回调必须带着它）。
/// 单独抽出来是为了能单测（跨域不该串味）。
class LibraryCookieJar {
  /// 域 → (名字 → 值)。**按域分开存**：给某个请求拼 Cookie 头时只带它自己域能用的，
  /// 否则会把 zjuam 的 SSO cookie 也送给业务站（单测抓到过这个）。
  final Map<String, Map<String, String>> _byDomain = <String, Map<String, String>>{};

  void absorb(Uri uri, Iterable<Cookie> cookies) {
    for (final cookie in cookies) {
      final domain = (cookie.domain == null || cookie.domain!.isEmpty)
          ? uri.host
          : cookie.domain!.replaceFirst(RegExp(r'^\.'), '');
      final bucket = _byDomain.putIfAbsent(domain, () => <String, String>{});
      if (cookie.value.isEmpty) {
        bucket.remove(cookie.name);
      } else {
        bucket[cookie.name] = cookie.value;
      }
    }
  }

  /// 这个请求该带的 Cookie 头（域名匹配：精确，或它的父域）
  String headerFor(Uri uri) {
    final parts = <String>[];
    _byDomain.forEach((domain, cookies) {
      if (uri.host == domain || uri.host.endsWith('.' + domain)) {
        cookies.forEach((name, value) => parts.add(name + '=' + value));
      }
    });
    return parts.join('; ');
  }

  bool get isEmpty => length == 0;

  int get length =>
      _byDomain.values.fold(0, (sum, bucket) => sum + bucket.length);

  void clear() => _byDomain.clear();
}

class LibrarySpider {
  LibrarySpider({
    required this.username,
    required this.password,
    HttpClient? httpClient,
  }) : _client = httpClient ?? HttpClient();

  static const String host = 'https://booking.lib.zju.edu.cn';
  static const String casServiceUrl = host + '/api/cas/cas';

  final String username;
  final String password;
  final HttpClient _client;
  final LibraryCookieJar _jar = LibraryCookieJar();

  bool _loggedIn = false;

  bool get loggedIn => _loggedIn;

  void close() => _client.close(force: true);

  /// 登录：拿 SSO → 申请 CAS ticket → 消费回调 → 验证
  Future<void> login() async {
    final sso = await ZjuAm.getSsoCookie(_client, username, password);
    if (sso == null) {
      throw LibraryAuthException('图书馆预约：统一身份认证没拿到登录态');
    }
    // 1) 先走一次业务入口，让后端下发它自己的 PHPSESSID（phpCAS 的会话）
    await _primeSession();
    // 2) 申请一次性 ticket，并**立刻**完整访问回调 —— 只拿 Location 不算数
    final callback = await ZjuAm.getServiceCallback(
      _client,
      sso,
      Uri.parse(casServiceUrl),
      context: '图书馆预约登录',
    );
    await _consumeCasCallback(callback);
    // 3) 用业务接口确认不是匿名
    _loggedIn = true;
    try {
      await myInfo();
    } on LibraryAuthException {
      _loggedIn = false;
      rethrow;
    }
    DiagnosticLogService.instance.record(
      module: '图书馆预约',
      operation: 'login',
      message: 'CAS 登录完成',
    );
  }

  Future<void> _primeSession() async {
    try {
      final request = await _client.getUrl(Uri.parse(casServiceUrl)).timeout(
            const Duration(seconds: 10),
          );
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 10));
      _jar.absorb(Uri.parse(casServiceUrl), response.cookies);
      await response.drain<void>();
    } on Object {
      // 拿不到就算了：回调那一步后端也会建会话
    }
  }

  Future<void> _consumeCasCallback(Uri callback) async {
    final request = await _client.getUrl(callback).timeout(const Duration(seconds: 12));
    // 不跟跳转：ticket 的校验在这一次请求里就完成了，后面的页面是 H5，不用下
    request.followRedirects = false;
    final cookieHeader = _jar.headerFor(Uri.parse(casServiceUrl));
    if (cookieHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }
    final response = await request.close().timeout(const Duration(seconds: 12));
    _jar.absorb(callback, response.cookies);
    await response.drain<void>();
    if (response.statusCode >= 500) {
      throw LibraryAuthException('图书馆预约：CAS 回调失败（HTTP ' + response.statusCode.toString() + '）');
    }
  }

  // ================= 业务接口 =================

  /// 公告（免登录）—— 用来快速判断"网络通不通、接口变没变"
  Future<List<LibraryNotice>> notices() async {
    final body = await post('/api/index/notice', <String, dynamic>{});
    return noticesFrom(body);
  }

  /// 公告响应的解析（纯函数，方便用实测 fixture 单测）
  static List<LibraryNotice> noticesFrom(Object? response) {
    if (response is! Map) return <LibraryNotice>[];
    final body = Map<String, dynamic>.from(response);
    final data = body['data'];
    final list = data is Map ? data['data'] : null;
    if (list is! List) return <LibraryNotice>[];
    final result = <LibraryNotice>[];
    for (final item in list) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      result.add(LibraryNotice(
        map['id']?.toString() ?? '',
        map['title']?.toString() ?? '',
        map['create_time']?.toString() ?? map['created_at']?.toString() ?? '',
      ));
    }
    return result;
  }

  /// 我的信息 / 我的预约入口
  Future<Map<String, dynamic>> myInfo() => post('/api/Member/my', <String, dynamic>{});

  /// 我的座位预约
  Future<Map<String, dynamic>> mySeats() => post('/api/Member/seat', <String, dynamic>{});

  /// 我的研讨间预约
  Future<Map<String, dynamic>> myRooms() => post('/api/Member/room', <String, dynamic>{});

  /// 馆/区树（做"哪里还有座"要用它拿到 areaId）
  Future<Map<String, dynamic>> seatTree() => post('/api/Seat/tree', <String, dynamic>{});

  /// 某一天的座位情况
  Future<Map<String, dynamic>> seatMap({
    required String areaId,
    required String date,
  }) =>
      post('/api/seat/map', <String, dynamic>{'areaId': areaId, 'date': date});

  /// 统一 POST：带上会话 cookie，处理"未登录"与传输错误
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> payload) async {
    final uri = Uri.parse(host + path);
    HttpClientRequest request;
    try {
      request = await _client.postUrl(uri);
    } on Object catch (error) {
      throw LibraryAuthException('图书馆预约：连不上（' + error.toString() + '）');
    }
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json;charset=UTF-8');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json;charset=UTF-8');
    request.headers.set('X-Requested-With', 'XMLHttpRequest');
    final cookieHeader = _jar.headerFor(uri);
    if (cookieHeader.isNotEmpty) request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    request.write(jsonEncode(payload));

    HttpClientResponse response;
    try {
      response = await request.close().timeout(const Duration(seconds: 15));
    } on Object catch (error) {
      throw LibraryAuthException('图书馆预约：请求超时或中断（' + error.toString() + '）');
    }
    _jar.absorb(uri, response.cookies);
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw LibraryAuthException('图书馆预约：HTTP ' + response.statusCode.toString());
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw LibraryAuthException('图书馆预约：返回格式不认识');
    }
    final body = Map<String, dynamic>.from(decoded);
    final code = body['code'];
    if (code == 10001) {
      _loggedIn = false;
      throw LibraryAuthException('图书馆预约：登录已失效（您尚未登录）');
    }
    return body;
  }

  /// 从"我的预约"响应里尽力挑出预约条目（字段名待真数据确认，见类注释）
  static List<LibraryReservation> reservationsFrom(Object? response) {
    final result = <LibraryReservation>[];
    void walk(Object? node) {
      if (node is List) {
        for (final item in node) {
          walk(item);
        }
        return;
      }
      if (node is Map) {
        final map = Map<String, dynamic>.from(node);
        final parsed = LibraryReservation.fromJson(map);
        if (parsed != null) result.add(parsed);
        for (final value in map.values) {
          if (value is List) walk(value);
        }
      }
    }

    walk(response);
    return result;
  }
}
