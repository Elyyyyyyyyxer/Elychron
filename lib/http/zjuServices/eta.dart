import 'dart:io';

import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/http/zjuServices/response_utils.dart';
import 'package:celechron/model/session.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/utils/tuple.dart';

/// 智慧研工（eta）—— 课表的**备用来源**。
///
/// 为什么需要它：本科教务（zdbk）在选课、排课期间会出现「请求成功但课表为空」，
/// 这时 zdbk 一条课次都给不出来（实测 2026-09-13 一次刷新里 8 个学期查询全部 0 行），
/// 而 eta 的课表接口同期是有数据的。
///
/// 与 zdbk 相比，这个接口的返回干净得多：直接给周几、半学期、起止节次、单双周，
/// 还带课程代码（[kcdm]）—— zdbk 不给课号，App 只能拿「学期 + 课程名」拼 key。
///
/// 局限：它只提供**当前学年学期**的课表，历史学期一律返回空。所以只当兜底，
/// 正常路径仍然走 zdbk。
class Eta {
  /// 业务接口走 https：站点到处给的是 http 地址，但直接请求 http 会 302 跳到 https。
  static const String _baseUrl = 'https://eta.zju.edu.cn/zftal-xgxt-web';

  /// 站点自己用的 CAS service 地址，照抄即可（换成别的路径会被判未登录）。
  /// 这里保持 http —— 与站点一致，票据才认；跳转回来时再升到 https。
  static const String _loginService =
      'http://eta.zju.edu.cn/zftal-xgxt-web/teacher/xtgl/index/check.zf';

  /// 登录后由 eta 签发的会话 Cookie（JSESSIONID 等），调用业务接口时原样带回。
  List<Cookie> _sessionCookies = const [];

  bool get isLoggedIn => _sessionCookies.isNotEmpty;

  /// 用统一身份认证的 SSO Cookie 换 eta 的会话。
  ///
  /// 两步和教务网一样：先拿 service 跳转地址（带 ST 票据），再访问它让业务站签发 Cookie。
  Future<void> login(HttpClient httpClient, Cookie ssoCookie) async {
    _sessionCookies = const [];

    var request = await httpClient
        .getUrl(Uri.parse(
            'https://zjuam.zju.edu.cn/cas/login?service=${Uri.encodeComponent(_loginService)}'))
        .timeout(const Duration(seconds: 8),
            onTimeout: () => throw requestTimeout());
    request.followRedirects = false;
    request.cookies.add(ssoCookie);
    var response = await request.close().timeout(const Duration(seconds: 8),
        onTimeout: () => throw requestTimeout());
    final firstBody =
        await readResponseBody(response, context: '智慧研工 CAS 登录');

    var location = response.headers.value(HttpHeaders.locationHeader);
    if (!response.isRedirect || location == null) {
      throw AuthenticationExpiredException(
          '智慧研工登录：统一身份认证凭据无效；HTTP ${response.statusCode}'
          '；Location ${location ?? '<缺失>'}'
          '；响应摘要：${responseSummary(firstBody)}');
    }
    // 站点给的 service 是 http，跟随跳转时升到 https（与教务网同样的处理）。
    if (location.startsWith('http://')) {
      location = location.replaceFirst('http://', 'https://');
    }

    request = await httpClient.getUrl(Uri.parse(location)).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw requestTimeout());
    request.followRedirects = false;
    response = await request.close().timeout(const Duration(seconds: 8),
        onTimeout: () => throw requestTimeout());
    final secondBody = await readResponseBody(response, context: '智慧研工登录');

    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden ||
        bodyIndicatesAuthenticationFailure(secondBody)) {
      throw AuthenticationExpiredException(
          '智慧研工登录态失效；HTTP ${response.statusCode}'
          '；响应摘要：${responseSummary(secondBody)}');
    }
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw ExceptionWithMessage('智慧研工登录失败；HTTP ${response.statusCode}'
          '；响应摘要：${responseSummary(secondBody)}');
    }

    final issued = response.cookies
        .where((cookie) => cookie.name.isNotEmpty && cookie.value.isNotEmpty)
        .toList();
    if (issued.isEmpty) {
      throw ExceptionWithMessage(
          '智慧研工登录未签发会话 Cookie；HTTP ${response.statusCode}'
          '；响应摘要：${responseSummary(secondBody)}');
    }
    _sessionCookies = issued;
  }

  /// 拉取某个学年学期的课表（[xnxq] 形如 `2026-2027-1`）。
  ///
  /// 返回的第一个元素是异常；调用方据此决定是否记降级，而不是直接当成失败。
  Future<Tuple<Exception?, List<Session>>> getTimetable(
      HttpClient httpClient, String xnxq) async {
    final context = '智慧研工课表接口（学年学期 $xnxq）';
    final uri = Uri.parse('$_baseUrl/student/xtgl/index/getTableKcb.zf'
        '?xnxq=${Uri.encodeQueryComponent(xnxq)}');
    try {
      if (_sessionCookies.isEmpty) {
        throw AuthenticationExpiredException('智慧研工未登录或会话已失效');
      }
      final request = await httpClient.getUrl(uri).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw requestTimeout());
      request.followRedirects = false;
      for (final cookie in _sessionCookies) {
        request.cookies.add(cookie);
      }
      final response = await request.close().timeout(const Duration(seconds: 8),
          onTimeout: () => throw requestTimeout());
      final body = await readResponseBody(response, context: context);

      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw AuthenticationExpiredException(
            '$context：登录态失效；HTTP ${response.statusCode}');
      }
      validateResponse(
        response: response,
        body: body,
        context: context,
        expectJson: true,
        requestUri: uri,
      );

      final payload = decodeJsonMap(body, context: '$context；HTTP ${response.statusCode}');
      final sessions = parseEtaTimetable(payload);
      DiagnosticLogService.instance.record(
        module: '课表',
        operation: 'eta',
        requestUri: uri,
        statusCode: response.statusCode,
        message: '$context：解析出 ${sessions.length} 条',
      );
      return Tuple(null, sessions);
    } on Object catch (error, stackTrace) {
      // 兜底来源失败不该拖垮整次刷新，由调用方决定怎么记录。
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: '课表',
        operation: 'eta',
        requestUri: uri,
        message: '$context：失败',
        error: error,
        stackTrace: stackTrace,
      );
      return Tuple(
        exceptionFrom(error,
            context: context, requestUri: uri, stackTrace: stackTrace),
        const <Session>[],
      );
    }
  }
}

/// 把 eta 的课表响应解析成 [Session] 列表。**纯函数**，便于单测。
///
/// 响应形如：
/// ```json
/// {"code":0,"data":{"kbList":{"1":[{"xqj":1,"xxq":"秋冬","ksj":6,"ks":1,
///   "sfqd":1,"dsz":"all","ke":[{"kcmc":"普通化学（H）","rkjs":"王勇",
///   "jsmc":"紫金港东1B-302","kcdm":"…"}]}]},"sjkc":[…]}}
/// ```
List<Session> parseEtaTimetable(Map<String, dynamic> payload) {
  final data = asStringMap(payload['data']);
  final kbList = data == null ? null : data['kbList'];
  if (kbList is! Map) return const <Session>[];

  final sessions = <Session>[];
  for (final value in kbList.values) {
    for (final item in asDynamicList(value) ?? const []) {
      final entry = asStringMap(item);
      if (entry == null) continue;
      final session = sessionFromEtaEntry(entry);
      if (session != null) sessions.add(session);
    }
  }
  return sessions;
}

/// 单条 eta 课表记录 → [Session]；缺关键字段时返回 null（跳过而不是抛异常）。
Session? sessionFromEtaEntry(Map<String, dynamic> entry) {
  final dayOfWeek = asInt(entry['xqj']);
  final firstPeriod = asInt(entry['ksj']);
  if (dayOfWeek == null || firstPeriod == null || firstPeriod <= 0) return null;

  final courses = asDynamicList(entry['ke']);
  final first = courses == null || courses.isEmpty
      ? null
      : asStringMap(courses.first);
  final name = asString(first?['kcmc']);
  if (name == null || name.trim().isEmpty) return null;

  // 节数与起始节次给出占用的连续节次；异常值按 1 节处理。
  final length = asInt(entry['ks']) ?? 1;
  final span = length > 0 ? length : 1;

  final session = Session.empty()
    ..confirmed = asInt(entry['sfqd']) == 1
    ..dayOfWeek = dayOfWeek < 1 ? 1 : (dayOfWeek > 7 ? 7 : dayOfWeek)
    // 课程名里的英文括号统一成中文括号，和 zdbk 路径保持一致
    ..name = name.replaceAll('(', '（').replaceAll(')', '）')
    ..teacher = asString(first?['rkjs']) ?? '未知教师'
    ..location = asString(first?['jsmc'])
    ..time = List<int>.generate(span, (index) => firstPeriod + index);

  // 半学期：秋冬（或缺失）算两边都上，只写「秋」/「冬」时按其归类。
  final half = asString(entry['xxq']) ?? '';
  final firstHalf = half.contains('秋') || half.contains('春');
  final secondHalf = half.contains('冬') || half.contains('夏');
  session.firstHalf = firstHalf || !secondHalf;
  session.secondHalf = secondHalf || !firstHalf;

  // 单双周：eta 用 all / single / double（也兼容数字码）。
  final repeat = (asString(entry['dsz']) ?? '').toLowerCase();
  final oddOnly = repeat == 'single' || repeat == '1' || repeat == '单';
  final evenOnly = repeat == 'double' || repeat == '2' || repeat == '双';
  session.oddWeek = !evenOnly;
  session.evenWeek = !oddOnly;

  return session;
}
