import 'package:celechron/mod/ai/deepseek.dart';
import 'package:celechron/mod/ai/model_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模型名自动解析的回归测试。
///
/// DeepSeek 每次迭代都会换模型名（`deepseek-chat` → `deepseek-flash`），
/// 这些用例把「换名字之后应用还能不能自己跟上」这件事钉住，
/// 而且全部离线，不花一分钱 API 费用。
void main() {
  group('候选排序：别名优先、避开贵档与不适用的模型', () {
    test('别名式名字优先于带版本号的同类', () {
      final ranked = ModelResolver.rank(<String>[
        'deepseek-v4-flash',
        'deepseek-flash',
      ]);
      expect(ranked.first, 'deepseek-flash');
    });

    test('官方改名后（出现 flash-2）仍挑得出可用的', () {
      final ranked = ModelResolver.rank(<String>[
        'deepseek-flash-2',
        'deepseek-flash',
        'deepseek-v4.1-pro',
      ]);
      expect(ranked, isNotEmpty);
      expect(ranked.first, 'deepseek-flash');
      expect(ranked.contains('deepseek-v4.1-pro'), isFalse,
          reason: '贵档不该被自动选中');
    });

    test('只有贵档时才允许退回（allowExpensive）', () {
      final ids = <String>['deepseek-v4-pro', 'deepseek-reasoner'];
      expect(ModelResolver.rank(ids), isEmpty);
      expect(ModelResolver.rank(ids, allowExpensive: true), isNotEmpty);
    });

    test('排除多模态 / 实验 / 嵌入类模型', () {
      final ranked = ModelResolver.rank(<String>[
        'deepseek-v4-flash-vision-exp',
        'deepseek-flash-vision',
        'deepseek-embedding',
        'deepseek-coder',
        'text-embedding-3',
        'deepseek-flash',
      ]);
      expect(ranked, <String>['deepseek-flash']);
    });

    test('空列表与纯空白不炸', () {
      expect(ModelResolver.rank(<String>[]), isEmpty);
      expect(ModelResolver.rank(<String>['', '   ']), isEmpty);
    });

    test('去重且保持可用', () {
      final ranked = ModelResolver.rank(<String>['a-flash', 'a-flash']);
      expect(ranked.length, 1);
    });

    test('选择理由是人话', () {
      expect(ModelResolver.explain('deepseek-flash'), contains('别名'));
      expect(ModelResolver.explain('whatever-1234'), isNotEmpty);
    });
  });

  group('模型失效错误的识别（决定要不要自愈重试）', () {
    test('官方常见文案 Model Not Exist', () {
      expect(
          ModelResolver.looksLikeModelError('模型服务返回：Model Not Exist'), isTrue);
    });

    test('英文变体', () {
      expect(ModelResolver.looksLikeModelError('model_not_found'), isTrue);
      expect(
          ModelResolver.looksLikeModelError(
              'The model `deepseek-flash` does not exist'),
          isTrue);
      expect(
          ModelResolver.looksLikeModelError('invalid model: whatever'), isTrue);
    });

    test('中文变体', () {
      expect(ModelResolver.looksLikeModelError('模型不存在'), isTrue);
      expect(ModelResolver.looksLikeModelError('该模型已下线'), isTrue);
    });

    test('不该误判：401 / 网络 / 余额', () {
      expect(ModelResolver.looksLikeModelError('API key 无效或已失效（401）'), isFalse);
      expect(ModelResolver.looksLikeModelError('连不上模型服务：连接被拒绝'), isFalse,
          reason: '提到「模型服务」但没有"不存在/无效"，不该触发重解析');
      expect(ModelResolver.looksLikeModelError('账户余额不足（402）'), isFalse);
      expect(ModelResolver.looksLikeModelError('请求超时，检查网络后重试'), isFalse);
    });
  });

  group('/models 返回体解析', () {
    test('标准 OpenAI 格式', () {
      const body = '{"object":"list","data":['
          '{"id":"deepseek-flash","object":"model","owned_by":"deepseek"},'
          '{"id":"deepseek-v4-pro","object":"model","owned_by":"deepseek"}]}';
      expect(DeepSeekClient.parseModelIds(body),
          <String>['deepseek-flash', 'deepseek-v4-pro']);
    });

    test('有些中转服务返回 {模型名: {...}}', () {
      const body = '{"data":{"gpt-4o-mini":{},"claude-3-haiku":{}}}';
      final ids = DeepSeekClient.parseModelIds(body);
      expect(ids.length, 2);
      expect(ids.contains('gpt-4o-mini'), isTrue);
    });

    test('data 直接是字符串数组', () {
      expect(DeepSeekClient.parseModelIds('{"data":["a","b"]}'),
          <String>['a', 'b']);
    });

    test('坏 JSON / 缺字段一律返回空列表而不是抛异常', () {
      expect(DeepSeekClient.parseModelIds('not json'), isEmpty);
      expect(DeepSeekClient.parseModelIds('{}'), isEmpty);
      expect(DeepSeekClient.parseModelIds('[]'), isEmpty);
      expect(DeepSeekClient.parseModelIds('{"data":[{"noid":1}]}'), isEmpty);
    });
  });

  group('缓存新鲜度', () {
    test('null 视为过期', () {
      expect(ModelResolver.isFresh(null), isFalse);
    });

    test('刚取的是新鲜的，8 天前的是过期的', () {
      expect(ModelResolver.isFresh(DateTime.now()), isTrue);
      expect(
          ModelResolver.isFresh(
              DateTime.now().subtract(const Duration(days: 8))),
          isFalse);
    });
  });
}
