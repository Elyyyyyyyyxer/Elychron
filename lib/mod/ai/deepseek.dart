import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ============ AI 功能配置 ============
///
/// 三条硬规矩：
/// 1. **绝不把 API key 硬编码进 APK**——只能由用户在设置里自己填
/// 2. key 存在系统密钥库（Android Keystore / iOS Keychain），不进 Hive、不进备份
/// 3. 功能默认关闭；开启即意味着「待办文本会发给你配置的模型服务商」，必须告知
class AiConfig {
  AiConfig._();

  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const String defaultModel = 'deepseek-chat';

  /// 可选的模型（DeepSeek 官方两个）
  static const List<String> models = <String>[
    'deepseek-chat',
    'deepseek-reasoner',
  ];

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kEnabled = 'ai_enabled';
  static const _kApiKey = 'ai_api_key';
  static const _kBaseUrl = 'ai_base_url';
  static const _kModel = 'ai_model';

  /// 每次改动都会 bump，界面用它触发刷新（避免把 Rx 依赖带进这个纯工具类）
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool _enabled = false;
  static String _apiKey = '';
  static String _baseUrl = defaultBaseUrl;
  static String _model = defaultModel;
  static bool _loaded = false;

  static bool get enabled => _enabled;
  static String get apiKey => _apiKey;
  static String get baseUrl => _baseUrl.isEmpty ? defaultBaseUrl : _baseUrl;
  static String get model => _model.isEmpty ? defaultModel : _model;

  static bool get isReady => _enabled && _apiKey.isNotEmpty;

  /// key 打码显示：sk-abc…xyz
  static String get maskedKey {
    if (_apiKey.isEmpty) return '';
    if (_apiKey.length <= 10) return '••••';
    return '${_apiKey.substring(0, 6)}…${_apiKey.substring(_apiKey.length - 4)}';
  }

  static Future<void> load() async {
    if (_loaded) return;
    try {
      _enabled = (await _storage.read(key: _kEnabled)) == 'true';
      _apiKey = (await _storage.read(key: _kApiKey)) ?? '';
      _baseUrl = (await _storage.read(key: _kBaseUrl)) ?? defaultBaseUrl;
      _model = (await _storage.read(key: _kModel)) ?? defaultModel;
    } catch (_) {
      // 密钥库不可用时退化为「未配置」，不阻断 App
    }
    _loaded = true;
    revision.value++;
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _write(_kEnabled, value ? 'true' : 'false');
  }

  static Future<void> setApiKey(String value) async {
    _apiKey = value.trim();
    await _write(_kApiKey, _apiKey);
  }

  static Future<void> setBaseUrl(String value) async {
    _baseUrl = value.trim().isEmpty ? defaultBaseUrl : value.trim();
    await _write(_kBaseUrl, _baseUrl);
  }

  static Future<void> setModel(String value) async {
    _model = value;
    await _write(_kModel, _model);
  }

  static Future<void> clearApiKey() async {
    _apiKey = '';
    await _write(_kApiKey, '');
  }

  static Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
    revision.value++;
  }
}

/// ============ DeepSeek 客户端 ============
///
/// DeepSeek 的接口与 OpenAI 兼容，所以这个客户端换个 baseUrl 也能接别的服务商
/// （设置里可以改 baseUrl，方便接中转或本地模型）。
///
/// 只用 `dart:io` 的 `HttpClient`，不引入新依赖。
class DeepSeekClient {
  DeepSeekClient({String? apiKey, String? baseUrl, String? model})
      : _apiKey = apiKey ?? AiConfig.apiKey,
        _baseUrl = baseUrl ?? AiConfig.baseUrl,
        _model = model ?? AiConfig.model;

  final String _apiKey;
  final String _baseUrl;
  final String _model;

  static const Duration timeout = Duration(seconds: 60);

  /// 让模型返回 JSON 对象。
  ///
  /// [system] 里**必须出现 "json" 字样**（DeepSeek JSON 模式的硬性要求），
  /// 否则接口会直接报错。
  Future<Map<String, dynamic>> chatJson({
    required String system,
    required String user,
    double temperature = 0.2,
    Duration? timeout,
  }) async {
    final text = await chat(
      system: system,
      user: user,
      temperature: temperature,
      jsonMode: true,
      timeout: timeout,
    );
    final parsed = _extractJson(text);
    if (parsed == null) {
      throw AiException('模型返回的不是合法 JSON：${_snippet(text)}');
    }
    return parsed;
  }

  /// 普通对话
  Future<String> chat({
    required String system,
    required String user,
    double temperature = 0.3,
    bool jsonMode = false,
    Duration? timeout,
  }) async {
    if (_apiKey.isEmpty) throw AiException('还没有填 API key（设置 → AI 智能助手）');

    final client = HttpClient()
      ..connectionTimeout = timeout ?? DeepSeekClient.timeout;
    try {
      final request = await client
          .postUrl(Uri.parse('$_baseUrl/chat/completions'))
          .timeout(timeout ?? DeepSeekClient.timeout);
      request.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
      request.add(utf8.encode(jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
        'temperature': temperature,
        if (jsonMode) 'response_format': {'type': 'json_object'},
        'stream': false,
      })));

      final response =
          await request.close().timeout(timeout ?? DeepSeekClient.timeout);
      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode != 200) {
        throw AiException(_describeHttpError(response.statusCode, body));
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) throw AiException('接口返回了意外内容');
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw AiException('接口没有返回结果');
      }
      final first = choices.first;
      final content = first is Map ? (first['message']?['content']) : null;
      if (content is! String || content.trim().isEmpty) {
        throw AiException('模型返回了空内容');
      }
      return content;
    } on SocketException catch (error) {
      throw AiException('连不上模型服务：${error.message}');
    } on TimeoutException {
      throw AiException('请求超时，检查网络后重试');
    } on HandshakeException {
      throw AiException('HTTPS 握手失败，检查网络环境');
    } finally {
      client.close(force: true);
    }
  }

  /// 把错误翻译成人话，别把 JSON 原文糊到用户脸上
  static String _describeHttpError(int status, String body) {
    final detail = _readError(body);
    switch (status) {
      case 401:
        return 'API key 无效或已失效（401）';
      case 402:
        return '账户余额不足（402）$detail';
      case 429:
        return '请求太频繁或超出限额（429），等一会儿再试';
      case 400:
        return '请求被拒绝（400）$detail';
      case 500:
      case 502:
      case 503:
        return '模型服务暂时不可用（$status），稍后再试';
      default:
        return '接口返回 $status$detail';
    }
  }

  static String _readError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return '：${error['message']}';
        }
        if (error is String) return '：$error';
      }
    } catch (_) {}
    return '';
  }

  /// 容忍模型把 JSON 包在 ```json 里，或者前后带了说明文字
  static Map<String, dynamic>? _extractJson(String text) {
    final trimmed = text.trim();
    final direct = _tryParse(trimmed);
    if (direct != null) return direct;

    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(trimmed);
    if (fenced != null) {
      final inner = _tryParse(fenced.group(1)!.trim());
      if (inner != null) return inner;
    }

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return _tryParse(trimmed.substring(start, end + 1));
    }
    return null;
  }

  static Map<String, dynamic>? _tryParse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static String _snippet(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 120 ? flat : '${flat.substring(0, 120)}…';
  }
}

/// AI 相关的错误，message 直接可以给用户看
class AiException implements Exception {
  AiException(this.message);

  final String message;

  @override
  String toString() => message;
}
