import 'dart:convert';
import 'dart:io';

import 'package:celechron/model/todo.dart';

/// ===== PTA（拼题A / pintia.cn）作业读取（2026-10-01）=====
///
/// 侦察结论见 docs/PTA_RECON.md，要点都是**实测**来的：
/// - 认证只需要一个 cookie：PTASession（没有验证码，也不需要模拟浏览器签名）；
/// - 未登录时后端返回 **404 + error.code=USER_NOT_FOUND**，不是 401；
/// - 截止时间有两处：题目集自己的 endAt，以及题集里「考试」的 exam.endAt
///   （有 exam 时以它为准；实测两者常常一样）；
/// - 时间是 **UTC**（...Z）：2026-10-07T15:59:00Z = 北京 23:59。
///   这里原样塞进 Todo.endTime（DateTime 自带时区语义），界面统一走
///   toStringHumanReadable() 里的 toLocal()，所以不会差 8 小时。
/// - permission.permission 实测是 47（社区文档说 9/15），**不要硬编码**权限值，
///   判断能不能读只能靠 403/404。
class PtaAuthExpiredException implements Exception {
  PtaAuthExpiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PtaException implements Exception {
  PtaException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PtaSpider {
  PtaSpider({required this.cookie, HttpClient? httpClient})
      : _client = httpClient ?? HttpClient();

  static const String host = 'https://pintia.cn';
  static const String passportHost = 'https://passport.pintia.cn';
  static const Duration timeout = Duration(seconds: 20);

  /// 浏览器 UA：PTA 对非常规客户端有风控（实测裸请求会被 406 掉）
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  final String cookie;
  final HttpClient _client;

  void close() => _client.close(force: true);

  /// 还没截止的题目集（连同它们里面的考试）→ 作业列表
  Future<({List<Todo> todos, int skippedInClass})> fetchActive({
    DateTime? now,
    bool includeInClass = false,
  }) async {
    final moment = (now ?? DateTime.now()).toUtc().toIso8601String();
    final uri = Uri.parse(host + '/api/problem-sets').replace(
      queryParameters: <String, String>{
        'filter': jsonEncode(<String, String>{'endAtAfter': moment}),
      },
    );
    final body = await _getJson(uri, strict: true);
    final rawList = body['problemSets'];
    final problemSets = rawList is List ? rawList : const <dynamic>[];

    final examsBySetId = <String, Map<String, dynamic>?>{};
    for (final item in problemSets) {
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      // 单个题集读不到（403 没权限 / 404 没有考试）不算错，跳过就行。
      examsBySetId[id] =
          await _getJson(Uri.parse(host + '/api/problem-sets/' + id + '/exams'), strict: false);
    }
    return todosFrom(
      problemSets: problemSets,
      examsBySetId: examsBySetId,
      includeInClass: includeInClass,
    );
  }

  /// 校验 cookie 还有没有效；返回昵称（设置页的「测试连接」用）
  Future<String> whoAmI() async {
    final body = await _getJson(Uri.parse(passportHost + '/api/u/current'), strict: true);
    final user = body['user'];
    if (user is! Map) return '';
    return user['nickname']?.toString() ?? '';
  }

  // ================= 纯函数（单测钉的就是这几条）=================

  /// 题目集 + 各自的 /exams 响应 → 作业列表
  ///
  /// [includeInClass] 为 false（默认）时**跳过当堂类型**（当堂实验 / 随堂练习 /
  /// 上机考试）—— 用户要求：「其中一个作业是当堂实验 …… 这种类型的显然不能
  /// 成为作业待办」。跳过几条会一并返回，好让界面把话说清楚。
  static ({List<Todo> todos, int skippedInClass}) todosFrom({
    required List<dynamic> problemSets,
    required Map<String, Map<String, dynamic>?> examsBySetId,
    bool includeInClass = false,
  }) {
    final todos = <Todo>[];
    var skippedInClass = 0;
    for (final item in problemSets) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final setId = map['id']?.toString() ?? '';
      if (setId.isEmpty) continue;

      final response = examsBySetId[setId];
      final rawExam = response == null ? null : response['exam'];
      final exam = rawExam is Map ? Map<String, dynamic>.from(rawExam) : null;

      final endAt = deadlineOf(problemSet: map, exam: exam);
      // 没有截止时间的题目集不变成待办（待办没有时间就没有意义）。
      if (endAt == null || endAt.isEmpty) continue;

      // 当堂类型（当堂实验 / 随堂练习 / 上机）不是"课后作业"，不建待办。
      final startAt = map['startAt']?.toString();
      final startTime = startAt == null ? null : DateTime.tryParse(startAt);
      final endTime = DateTime.tryParse(endAt);
      if (!includeInClass &&
          startTime != null &&
          endTime != null &&
          looksLikeInClass(startTime, endTime)) {
        skippedInClass++;
        continue;
      }

      // id 必须**跨刷新稳定**，否则每次刷新都会被当成新作业，待办会重复长出来。
      final examId = exam?['id']?.toString() ?? '';
      final id = exam == null || examId.isEmpty
          ? 'pta:' + setId
          : 'pta:' + setId + ':' + examId;

      todos.add(Todo.fromJson(<String, dynamic>{
        'id': id,
        'title': map['name']?.toString() ?? 'PTA 作业',
        'course_name': map['organizationName']?.toString() ?? 'PTA',
        'end_time': endAt,
      }));
    }
    return (todos: todos, skippedInClass: skippedInClass);
  }

  /// 是不是「当堂类型」（当堂实验 / 随堂练习 / 上机考试）？
  ///
  /// 判据用**时间窗口**而不是名字 —— 实测（2026-10-01，9 条真实题目集）：
  /// 当堂类窗口 1.2 / 2.5 / 6.6 / 8.8 小时（**都在同一天内**），
  /// 课后作业 152 / 169 / 177 小时（跨 6~7 天），中间是巨大的空档；
  /// 而名字只有一部分带「实验」「作业」，靠名字一定会误判
  /// （实测有 3 条当堂类名字里一个特征词都没有）。
  ///
  /// 所以只认一条：起止在**同一天**（按设备本地时区，也就是学生的北京时间）。
  static bool looksLikeInClass(DateTime start, DateTime end) {
    final from = start.toLocal();
    final to = end.toLocal();
    return from.year == to.year && from.month == to.month && from.day == to.day;
  }

  /// 截止时间：题集里有「考试」就听考试的，否则用题目集自己的
  static String? deadlineOf({
    required Map<String, dynamic> problemSet,
    Map<String, dynamic>? exam,
  }) {
    final fromExam = exam == null ? null : exam['endAt']?.toString();
    if (fromExam != null && fromExam.isNotEmpty) return fromExam;
    final fromSet = problemSet['endAt']?.toString();
    if (fromSet == null || fromSet.isEmpty) return null;
    return fromSet;
  }

  // ================= HTTP =================

  Future<Map<String, dynamic>> _getJson(Uri uri, {required bool strict}) async {
    HttpClientRequest request;
    try {
      request = await _client.getUrl(uri);
    } on Object catch (error) {
      throw PtaException('PTA 连不上：' + error.toString());
    }
    request.headers.set('Accept', 'application/json;charset=UTF-8');
    request.headers.set('Accept-Language', 'zh-CN');
    request.headers.set('Cookie', 'PTASession=' + cookie);
    request.headers.set('User-Agent', userAgent);

    HttpClientResponse response;
    try {
      response = await request.close().timeout(timeout);
    } on Object catch (error) {
      throw PtaException('PTA 请求超时或中断：' + error.toString());
    }
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode == 200) {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    }

    final authExpired = response.statusCode == 401 ||
        response.statusCode == 403 ||
        body.contains('USER_NOT_FOUND') ||
        body.contains('LOGIN_REQUIRED');
    if (!strict && (response.statusCode == 403 || response.statusCode == 404)) {
      return <String, dynamic>{}; // 没权限 / 没有考试的题集：跳过
    }
    if (authExpired) {
      throw PtaAuthExpiredException('PTA 登录已过期，请重新粘贴 PTASession');
    }
    throw PtaException('PTA 返回 HTTP ' + response.statusCode.toString());
  }
}
