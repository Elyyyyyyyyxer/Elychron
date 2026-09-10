import 'dart:convert';

import 'package:celechron/mod/ai/deepseek.dart';

/// ============ 模型名自动解析 ============
///
/// 背景：DeepSeek 迭代快，而且**每次都换模型名**（`deepseek-chat` →
/// `deepseek-flash`）。让用户手动改不现实，写死在代码里又必然过期。
///
/// 官方提供了机器可读的 `GET /models`（返回当前可用模型 id 列表），所以主路径是
/// **运行时问官方**，这里只负责：
///   1. 从返回的列表里挑一个「便宜档、适合文本任务」的（成本取向见下）
///   2. 缓存结果，并在调用报「模型不存在」时自愈重取
///
/// 成本取向（用户选择）：**默认只自动选便宜档**；`pro` / `reasoner` 这类贵模型
/// 只有在用户手动指定时才会用——避免因为官方改名而悄悄变贵。
class ModelResolver {
  ModelResolver._();

  /// 明显不适合「把通知解析成待办」的模型：多模态、实验版、嵌入、语音图像等
  static const List<String> excludedKeywords = <String>[
    'vision',
    'vl',
    'exp',
    'beta',
    'preview',
    'alpha',
    'coder',
    'code',
    'embedding',
    'embed',
    'audio',
    'image',
    'video',
    'ocr',
    'rerank',
    'tts',
    'asr',
  ];

  /// 贵档模型：自动选择时避开（用户手动选则照用）
  static const List<String> expensiveKeywords = <String>[
    'pro',
    'reasoner',
    'thinking',
    'max',
    'ultra',
    'plus',
  ];

  /// 便宜档线索：命中就是加分项
  static const List<String> cheapKeywords = <String>[
    'flash',
    'chat',
    'lite',
    'mini',
    'small',
    'turbo',
    'fast',
  ];

  /// 从可用列表里排序出候选（最合适的排最前）
  ///
  /// 规则（按权重）：
  /// 1. 排除 `excludedKeywords`
  /// 2. 非贵档优先（除非 [allowExpensive]）
  /// 3. **别名式名字优先**——不含版本数字（`deepseek-flash` 优于 `deepseek-v4-flash`），
  ///    因为官方会持续把别名指向最新，这正是我们要的「evergreen」
  /// 4. 命中 `cheapKeywords` 加分
  /// 5. 名字短的优先（别名通常更短）
  static List<String> rank(
    Iterable<String> ids, {
    bool allowExpensive = false,
  }) {
    final result = <String>[];
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      final lower = id.toLowerCase();
      if (excludedKeywords.any(lower.contains)) continue;
      if (!allowExpensive && expensiveKeywords.any(lower.contains)) continue;
      if (!result.contains(id)) result.add(id);
    }
    result.sort((String a, String b) {
      final byScore = _score(a).compareTo(_score(b));
      return byScore != 0 ? byScore : a.compareTo(b);
    });
    return result;
  }

  /// 越小越优先
  static int _score(String id) {
    final lower = id.toLowerCase();
    var score = 0;
    if (!RegExp(r'\d').hasMatch(id)) score -= 100; // 别名式
    if (cheapKeywords.any(lower.contains)) score -= 20;
    score += id.length; // 短的优先
    return score;
  }

  /// 给用户看的解释：为什么选中了它
  static String explain(String id) {
    final lower = id.toLowerCase();
    final reasons = <String>[];
    if (!RegExp(r'\d').hasMatch(id)) {
      reasons.add('这是官方别名，会一直指向最新模型');
    }
    if (cheapKeywords.any(lower.contains)) reasons.add('便宜档');
    if (reasons.isEmpty) reasons.add('按可用列表顺序选择');
    return reasons.join('，');
  }

  /// 判断一条错误信息是不是「模型名不对」这一类——这类错误可以自愈重试
  static bool looksLikeModelError(String message) {
    final lower = message.toLowerCase();
    const hints = <String>[
      'model',
      'does not exist',
      'not exist',
      'not_exist',
      'not found',
      'unknown model',
      'invalid model',
      'no such model',
      'unsupported model',
      'model_not_found',
      '已下线',
      '不存在',
      '无效',
    ];
    // 「model」单独出现太宽泛，必须配上"不存在/无效"之类的词
    final hasModelWord = lower.contains('model') || lower.contains('模型');
    final hasProblemWord = hints
        .where((hint) => hint != 'model')
        .any((hint) => lower.contains(hint));
    return hasModelWord && hasProblemWord;
  }

  /// 解析 `/models` 的返回体，取出 id 列表
  static List<String> parseModelsResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return <String>[];
      final data = decoded['data'];
      if (data is! List) return <String>[];
      final ids = <String>[];
      for (final item in data) {
        if (item is Map) {
          final id = item['id'];
          if (id is String && id.trim().isNotEmpty) ids.add(id.trim());
        } else if (item is String && item.trim().isNotEmpty) {
          ids.add(item.trim());
        }
      }
      return ids;
    } catch (_) {
      return <String>[];
    }
  }

  /// 解析并缓存当前该用的模型名（会打一次 /models）。
  ///
  /// 返回选中的模型名；拿不到列表时返回空字符串（调用方继续用兜底名）。
  /// 用户手动选定了模型时**不覆盖**他的选择，只更新可用列表。
  static Future<String> resolve({bool force = false}) async {
    await AiConfig.load();
    if (AiConfig.apiKey.isEmpty) return '';
    try {
      final ids = await DeepSeekClient().listModels();
      if (ids.isEmpty) return '';
      await AiConfig.cacheModelList(ids);
      if (AiConfig.isManualModel) return AiConfig.manualModel;

      var ranked = rank(ids);
      var usedExpensiveFallback = false;
      if (ranked.isEmpty) {
        // 便宜档全被过滤掉（比如官方只提供 pro）：退一步用贵档，但界面会说明
        ranked = rank(ids, allowExpensive: true);
        usedExpensiveFallback = ranked.isNotEmpty;
      }
      if (ranked.isEmpty) return '';
      final picked = ranked.first;
      await AiConfig.cacheResolvedModel(picked);
      lastAutoPickReason =
          usedExpensiveFallback ? '便宜档都不可用，暂时用了 $picked' : explain(picked);
      return picked;
    } on AiException {
      return '';
    }
  }

  /// 最近一次自动选择的原因（界面展示用）
  static String lastAutoPickReason = '';

  /// 执行一次调用；若因「模型名失效」失败，则重新解析模型名并重试一次。
  ///
  /// 这是「改名了用户也不会卡住」的关键：官方换名字后，第一次调用失败会被这里
  /// 识别出来，自动换成新名字重试，用户全程无感。
  static Future<T> withModelHealing<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AiException catch (error) {
      if (!looksLikeModelError(error.message)) rethrow;
      final healed = await resolve(force: true);
      if (healed.isEmpty) rethrow;
      return await action();
    }
  }

  /// 缓存是否还新鲜
  static bool isFresh(DateTime? fetchedAt,
      {Duration maxAge = const Duration(days: 7)}) {
    if (fetchedAt == null) return false;
    return DateTime.now().difference(fetchedAt) < maxAge;
  }
}
