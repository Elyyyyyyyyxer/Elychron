import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:celechron/mod/ai/ai_image.dart';
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

  /// 当前有效的模型名（2026-09 官方文档）：
  /// - `deepseek-flash` 指向最新的 **V4.1 Flash**，快、便宜、原生多模态
  /// - `deepseek-v4-pro` 是 Pro；官方公告 2026-09-14 12:00 起会路由到 V4.1 Flash
  ///
  /// 注意：`deepseek-chat` / `deepseek-reasoner` 是**过时名字**，别再用了。
  static const String defaultModel = 'deepseek-flash';

  static const List<String> models = <String>[
    'deepseek-flash',
    'deepseek-v4-pro',
  ];

  /// 过时模型名 → 现在的名字（老配置自动迁移，避免用户手里存着失效的名字）
  static const Map<String, String> _legacyModels = <String, String>{
    'deepseek-chat': 'deepseek-flash',
    'deepseek-coder': 'deepseek-flash',
    'deepseek-v3': 'deepseek-flash',
    'deepseek-v4-flash': 'deepseek-flash',
    'deepseek-v4-flash-vision-exp': 'deepseek-flash',
    'deepseek-reasoner': 'deepseek-v4-pro',
  };

  /// 界面上显示的模型名
  static String modelLabel(String id) {
    switch (id) {
      case 'deepseek-flash':
        return 'deepseek-flash （V4.1 Flash）';
      case 'deepseek-v4-pro':
        return 'deepseek-v4-pro （V4 Pro）';
      default:
        return id;
    }
  }

  /// 每个模型的用处说明
  static String modelNote(String id) {
    switch (id) {
      case 'deepseek-flash':
        return '推荐。最新 V4.1 Flash，快且便宜，解析文字、拆子待办够用';
      case 'deepseek-v4-pro':
        return 'Pro 型号；官方公告 2026-09-14 起会先路由到 V4.1 Flash';
      default:
        return '';
    }
  }

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kEnabled = 'ai_enabled';
  static const _kApiKey = 'ai_api_key';
  static const _kBaseUrl = 'ai_base_url';
  static const _kModel = 'ai_model';
  static const _kResolvedModel = 'ai_resolved_model';
  static const _kModelList = 'ai_model_list';
  static const _kModelListAt = 'ai_model_list_at';
  static const _kAutoSubtasks = 'ai_auto_subtasks';

  /// 每次改动都会 bump，界面用它触发刷新（避免把 Rx 依赖带进这个纯工具类）
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool _enabled = false;
  static String _apiKey = '';
  static String _baseUrl = defaultBaseUrl;

  /// 用户手动选定的模型；空字符串表示「自动」
  static String _manualModel = '';

  /// 自动解析出来的模型名（来自官方 /models）
  static String _resolvedModel = '';

  /// 最近一次从 /models 拿到的可用列表
  static List<String> _availableModels = <String>[];
  static DateTime? _modelsFetchedAt;
  static bool _loaded = false;

  /// 解析待办时是否自动生成子待办（用户可在设置里关掉）
  static bool _autoSubtasks = true;

  static bool get enabled => _enabled;
  static String get apiKey => _apiKey;
  static String get baseUrl => _baseUrl.isEmpty ? defaultBaseUrl : _baseUrl;

  /// 实际调用要用的模型名：**手动 > 自动解析 > 兜底常量**
  static String get model {
    if (_manualModel.isNotEmpty) return _manualModel;
    if (_resolvedModel.isNotEmpty) return _resolvedModel;
    return defaultModel;
  }

  static bool get isManualModel => _manualModel.isNotEmpty;
  static String get manualModel => _manualModel;
  static String get resolvedModel => _resolvedModel;
  static List<String> get availableModels =>
      List<String>.unmodifiable(_availableModels);
  static DateTime? get modelsFetchedAt => _modelsFetchedAt;

  /// 手动指定模型
  static Future<void> setModel(String value) async {
    _manualModel = value.trim();
    await _write(_kModel, _manualModel);
  }

  /// 回到「自动选择」
  static Future<void> setAutoModel() async {
    _manualModel = '';
    await _write(_kModel, '');
  }

  /// 缓存自动解析结果
  static Future<void> cacheResolvedModel(String value) async {
    _resolvedModel = value;
    await _write(_kResolvedModel, value);
  }

  /// 缓存 /models 拉到的列表
  static Future<void> cacheModelList(List<String> ids, {DateTime? at}) async {
    _availableModels = <String>[...ids];
    _modelsFetchedAt = at ?? DateTime.now();
    await _write(_kModelList, jsonEncode(_availableModels));
    await _write(_kModelListAt, _modelsFetchedAt!.toIso8601String());
  }

  static bool get isReady => _enabled && _apiKey.isNotEmpty;

  static bool get autoSubtasks => _autoSubtasks;

  static Future<void> setAutoSubtasks(bool value) async {
    _autoSubtasks = value;
    await _write(_kAutoSubtasks, value ? 'true' : 'false');
  }

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
      _autoSubtasks = (await _storage.read(key: _kAutoSubtasks)) != 'false';
      _apiKey = (await _storage.read(key: _kApiKey)) ?? '';
      _baseUrl = (await _storage.read(key: _kBaseUrl)) ?? defaultBaseUrl;
      _manualModel = (await _storage.read(key: _kModel)) ?? '';
      _resolvedModel = (await _storage.read(key: _kResolvedModel)) ?? '';
      final listRaw = await _storage.read(key: _kModelList);
      if (listRaw != null && listRaw.isNotEmpty) {
        final decoded = jsonDecode(listRaw);
        if (decoded is List) {
          _availableModels = decoded.whereType<String>().toList();
        }
      }
      final atRaw = await _storage.read(key: _kModelListAt);
      _modelsFetchedAt = atRaw == null ? null : DateTime.tryParse(atRaw);
      // 手里存着已退役的模型名就静默迁移，否则用户会在不知情的情况下调用失败
      if (_manualModel.isNotEmpty) {
        _manualModel = _legacyModels[_manualModel] ?? _manualModel;
        // 有可用列表时，用户手选的名字如果已经不在列表里就退回「自动」
        if (_availableModels.isNotEmpty &&
            !_availableModels.contains(_manualModel)) {
          _manualModel = '';
        }
        await _write(_kModel, _manualModel);
      }
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

  // setModel / setAutoModel 见上面（手动与自动双轨）

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
    List<AiImagePart> images = const <AiImagePart>[],
    double temperature = 0.2,
    Duration? timeout,
  }) async {
    final text = await chat(
      system: system,
      user: user,
      images: images,
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
    List<AiImagePart> images = const <AiImagePart>[],
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
          {
            'role': 'user',
            // 有图时 content 变成 parts 数组（官方 vision 文档的形状）
            'content': images.isEmpty
                ? user
                : <Map<String, dynamic>>[
                    {'type': 'text', 'text': user},
                    for (final image in images)
                      {
                        'type': 'image_url',
                        'image_url': {
                          'url': image.dataUri,
                          // 读截图里的小字必须用 high；low 会缩到 512×512 看不清
                          'detail': 'high',
                        },
                      },
                  ],
          },
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

  /// 拉取官方当前可用的模型列表（GET /models，OpenAI 兼容）
  ///
  /// 这是「模型名会变」这个问题的正解：不问代码里写死的名字，直接问官方。
  Future<List<String>> listModels({Duration? timeout}) async {
    if (_apiKey.isEmpty) {
      throw AiException('还没有填 API key（设置 → AI 智能助手）');
    }
    final limit = timeout ?? const Duration(seconds: 20);
    final client = HttpClient()..connectionTimeout = limit;
    try {
      final request =
          await client.getUrl(Uri.parse('$_baseUrl/models')).timeout(limit);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey');
      final response = await request.close().timeout(limit);
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw AiException(_describeHttpError(response.statusCode, body));
      }
      return parseModelIds(body);
    } on SocketException catch (error) {
      throw AiException('连不上模型服务：${error.message}');
    } on TimeoutException {
      throw AiException('拉取模型列表超时，检查网络后重试');
    } finally {
      client.close(force: true);
    }
  }

  /// 解析 /models 的返回体，取出模型 id 列表
  static List<String> parseModelIds(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return <String>[];
      final data = decoded['data'];
      final ids = <String>[];
      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            final id = item['id'];
            if (id is String && id.trim().isNotEmpty) ids.add(id.trim());
          } else if (item is String && item.trim().isNotEmpty) {
            ids.add(item.trim());
          }
        }
      } else if (data is Map) {
        // 有些中转服务直接返回 { "模型名": {...} } 这种形式
        for (final key in data.keys) {
          if (key is String && key.trim().isNotEmpty) ids.add(key.trim());
        }
      }
      return ids;
    } catch (_) {
      return <String>[];
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
