import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/calendar_bundled_config.dart';
import 'package:celechron/http/calendar_config_parser.dart';
import 'package:celechron/http/data_source_status.dart';
import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/http/zjuServices/response_utils.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/utils/tuple.dart';
import 'package:flutter/foundation.dart';

/// 获取并校验学期校历。
///
/// ===== 2026-09-17 用户拍板后的新口径 =====
///
/// 背景：校历来自**上游第三方静态站**（`http://calendar.celechron.top/`，明文 HTTP），
/// 用户实测"老是连不上"， 一失败就落缓存，缓存空就只能本地推算（节假日全空、考试周不准）。
///
/// 现在改成四件事：
/// 1. **随包内置一份**（`assets/calendar/<学年学期>.json`，见 [BundledCalendarConfig]）：
///    离线可用、首次安装就有；
/// 2. **每周才试一次远程**（[updateInterval]）：不是每次刷新都去敲那个不靠谱的站；
/// 3. 连上了就**比对差异、按新的来**（内容变了才覆盖，并在诊断里写明"已更新"）；
/// 4. 远程地址**先试 HTTPS、再回退 HTTP**（实测该站 HTTPS 握手失败，回退几乎是必然，
///    但先试一次的成本很低，哪天上游修好了自动受益）。
///
/// 降级顺序：**同学期缓存 → 随包内置 → 本地推算**（每一级都记诊断，来源写得清清楚楚）。
class TimeConfigService {
  static const _lastValidCacheKey = 'timeConfig_lastValid';

  /// 远程更新的最短间隔：一周。用户原话：每周进行一次尝试性连接更新。
  static const Duration updateInterval = Duration(days: 7);

  DatabaseHelper? _db;

  set db(DatabaseHelper? db) {
    _db = db;
  }

  String _attemptKey(String semesterId) => 'timeConfig_attempt_$semesterId';

  /// 现在该不该去试远程？（距上次**尝试**不足一周就跳过）
  ///
  /// 注意记的是"尝试"而不是"成功"：那个站可能长期连不上，
  /// 记成功会导致每次刷新都去重试同一个死站。
  bool shouldAttemptRemote(String semesterId, {DateTime? now}) {
    final current = now ?? DateTime.now();
    // ===== 历史学期根本不用试远程（2026-09-17）=====
    // 上学期的校历不可能再改；每次刷新都去敲一遍只是白费请求（那个站还老是挂）。
    final parts = semesterId.split('-');
    final startYear = parts.isEmpty ? null : int.tryParse(parts.first);
    if (startYear != null && startYear < academicYearStartFor(current)) {
      return false;
    }
    final raw = _db?.getCachedWebPage(_attemptKey(semesterId));
    return isCalendarRemoteUpdateDue(
      lastAttempt: raw == null ? null : DateTime.tryParse(raw),
      now: current,
      interval: updateInterval,
    );
  }

  Future<void> _markAttempt(String semesterId) async {
    try {
      await _db?.setCachedWebPage(
        _attemptKey(semesterId),
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // 记不上时间不影响本次结果，最多下次再试一遍
    }
  }

  Future<Tuple3<Exception?, String?, DataSourceStatus>> getConfig(
      HttpClient httpClient, String semesterId) async {
    final key = calendarObjectKeyForSemester(semesterId);
    final context = '校历接口（学年学期 $semesterId，请求类型 配置）';

    // ===== 一周之内不再打扰远程，直接用本地可用的那一份 =====
    if (!shouldAttemptRemote(semesterId)) {
      final local = await fallbackConfig(semesterId, context);
      DiagnosticLogService.instance.record(
        module: '校历',
        operation: semesterId,
        cacheUsed: true,
        message: '距上次尝试不足 ${updateInterval.inDays} 天，跳过远程；'
            '${local.status.label}（来源：${local.source}）',
      );
      return Tuple3(null, local.config, local.status);
    }

    // 先 HTTPS、不行再 HTTP（该站目前 HTTPS 握手失败，见类注释）
    final candidates = calendarConfigUriCandidates(semesterId);
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var i = 0; i < candidates.length; i++) {
      final uri = candidates[i];
      final isLast = i == candidates.length - 1;
      if (kDebugMode) {
        debugPrint('校历请求：URL=$uri，OSS Key=$key');
      }
      try {
        await _markAttempt(semesterId);
        return await _fetchOnce(
          httpClient,
          uri: uri,
          key: key,
          context: context,
          semesterId: semesterId,
        );
      } on Object catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (isLast) break;
        // 两种值得换下一个地址的情况：连不上/握手失败，或者这个地址上没有这份配置
        // （我们有镜像，Gitee/GitHub 上可能已经有了）。
        final worthAnotherTry = _isTransportFailure(error) ||
            error is CalendarConfigUnavailableException;
        if (!worthAnotherTry) break;
        DiagnosticLogService.instance.record(
          level: CelechronLogLevel.warning,
          module: '校历',
          operation: semesterId,
          requestUri: uri,
          message: '这个地址拿不到，换下一个候选：$error',
        );
      }
    }

    final fallback = await fallbackConfig(semesterId, context);
    DiagnosticLogService.instance.record(
      level: CelechronLogLevel.warning,
      module: '校历',
      operation: semesterId,
      cacheUsed: true,
      message: '实时请求失败，${fallback.status.label}'
          '（来源：${fallback.source}）；缓存时间=${fallback.cachedAt ?? '<无>'}',
      error: lastError,
      stackTrace: lastStackTrace,
    );
    return Tuple3(
      exceptionFrom(
        lastError ?? ExceptionWithMessage('$context：远程配置不可用'),
        context: context,
        stackTrace: lastStackTrace,
      ),
      fallback.config,
      fallback.status,
    );
  }

  /// 单次远程拉取（成功则落缓存；失败抛出去给上层决定是否换协议/兜底）
  Future<Tuple3<Exception?, String?, DataSourceStatus>> _fetchOnce(
    HttpClient httpClient, {
    required Uri uri,
    required String key,
    required String context,
    required String semesterId,
  }) async {
    final request = await httpClient.getUrl(uri).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw requestTimeout(),
        );
    request.followRedirects = false;
    final response = await request.close().timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw requestTimeout(),
        );
    final body = await readResponseBody(response, context: context);
    final contentType =
        response.headers.value(HttpHeaders.contentTypeHeader) ?? '<缺失>';
    final noSuchKey = response.statusCode == HttpStatus.notFound ||
        body.contains('<Code>NoSuchKey</Code>');

    if (noSuchKey) {
      // 这个地址上没有这份配置，**不代表别的地址也没有**（我们有镜像），
      // 所以这里抛出去让上层继续试下一个候选；全都 404 才是"真没发布"。
      throw CalendarConfigUnavailableException(
        details: [
          '接口：$context',
          '请求：${sanitizedRequestUri(uri)}',
          'OSS Key：$key',
          'HTTP 状态码：${response.statusCode}',
          'Content-Type：$contentType',
          '原始异常类型：NoSuchKey',
          '执行过重新登录：否',
          '执行过重试：否',
          '响应摘要：${responseSummary(body)}',
        ].join('\n'),
      );
    }

    validateResponse(
      response: response,
      body: body,
      context: context,
      expectJson: true,
      requestUri: uri,
    );
    decodeAndValidateCalendarConfig(
      body,
      context: '$context；HTTP ${response.statusCode}',
    );

    // ===== 比对差异、按新的来 =====
    final previous = _db?.getCachedWebPage('timeConfig_$semesterId') ??
        await BundledCalendarConfig.load(semesterId);
    final changed = previous == null ? null : previous.trim() != body.trim();

    await Future.wait([
      // 精确学期缓存用于恢复本学期；最后有效配置只提供节次时间模板。
      _db?.setCachedWebPage('timeConfig_$semesterId', body) ??
          Future<void>.value(),
      _db?.setCachedWebPage(_lastValidCacheKey, body) ?? Future<void>.value(),
      _db?.setCachedWebPage(
            'timeConfig_timestamp_$semesterId',
            DateTime.now().toUtc().toIso8601String(),
          ) ??
          Future<void>.value(),
    ]);
    DiagnosticLogService.instance.record(
      module: '校历',
      operation: semesterId,
      requestUri: uri,
      statusCode: response.statusCode,
      contentType: contentType,
      message: DataSourceStatus.live.label +
          (changed == null
              ? '（首次获取）'
              : changed
                  ? '（与上一份不同，已按新的覆盖）'
                  : '（与本地一致，未变化）'),
    );
    return Tuple3(null, body, DataSourceStatus.live);
  }

  bool _isTransportFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('timeout') ||
        text.contains('超时') ||
        text.contains('socket') ||
        text.contains('handshake') ||
        text.contains('connection') ||
        text.contains('网络') ||
        text.contains('tls') ||
        text.contains('certificate');
  }

  /// 本地可用的校历：**同学期缓存 → 随包内置 → 本地推算**
  Future<_CalendarFallback> fallbackConfig(
      String semesterId, String context) async {
    // 1) 精确缓存优先，因为其中的日期和调休只适用于对应学期。
    final exactCache = _db?.getCachedWebPage('timeConfig_$semesterId');
    if (exactCache != null) {
      try {
        decodeAndValidateCalendarConfig(
          exactCache,
          context: '$context 本地缓存',
        );
        return _CalendarFallback(
          exactCache,
          DataSourceStatus.cache,
          cachedAt: _db?.getCachedWebPage('timeConfig_timestamp_$semesterId'),
          source: '本地缓存',
        );
      } on Object catch (error, stackTrace) {
        DiagnosticLogService.instance.record(
          level: CelechronLogLevel.warning,
          module: '校历',
          operation: 'readExactCache',
          cacheUsed: false,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    // 2) 随包内置的那一份（用户 2026-09-17 拍板加的；离线也有、首次安装就有）
    final bundled = await BundledCalendarConfig.load(semesterId);
    if (bundled != null) {
      try {
        decodeAndValidateCalendarConfig(
          bundled,
          context: '$context 随包内置',
        );
        return _CalendarFallback(
          bundled,
          DataSourceStatus.cache,
          source: '随包内置',
        );
      } on Object catch (error, stackTrace) {
        DiagnosticLogService.instance.record(
          level: CelechronLogLevel.warning,
          module: '校历',
          operation: 'readBundled',
          cacheUsed: false,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    // 3) 其它学期缓存不能复用日期，只提取经过校验的 sessionTime 当模板
    Map<String, dynamic>? template;
    final lastValid = _db?.getCachedWebPage(_lastValidCacheKey);
    if (lastValid != null) {
      try {
        template = decodeAndValidateCalendarConfig(
          lastValid,
          context: '$context 上一份有效缓存',
        );
      } on Object catch (error, stackTrace) {
        DiagnosticLogService.instance.record(
          level: CelechronLogLevel.warning,
          module: '校历',
          operation: 'readTemplateCache',
          cacheUsed: false,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return _CalendarFallback(
      buildSafeDefaultCalendarConfig(
        semesterId,
        template: template,
      ),
      DataSourceStatus.fallback,
      source: '本地推算',
    );
  }
}

class _CalendarFallback {
  final String config;
  final DataSourceStatus status;
  final String? cachedAt;

  /// 这份配置是从哪来的（诊断与界面提示用）：本地缓存 / 随包内置 / 本地推算
  final String source;

  const _CalendarFallback(this.config, this.status,
      {this.cachedAt, this.source = '未知'});
}
