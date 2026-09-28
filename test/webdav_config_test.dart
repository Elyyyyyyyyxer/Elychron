import 'package:celechron/mod/webdav_config.dart';
import 'package:celechron/mod/webdav_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// ===== 全平台同步（W3）：配置层的纯函数 =====
///
/// 这里钉的都是"真机上踩过、而且用户完全猜不到原因"的坑：
/// 地址少个斜杠、从网页复制带引号、用户名大小写、占位模板没改就点测试。
void main() {
  group('normalizeUrl 把用户贴进来的地址修成能用的样子', () {
    test('只填域名时补上 https', () {
      expect(WebDavConfig.normalizeUrl('dav.jianguoyun.com/dav/'),
          'https://dav.jianguoyun.com/dav/');
    });

    test('末尾少了斜杠时补上（少了它请求会打到上一级）', () {
      expect(WebDavConfig.normalizeUrl('https://dav.jianguoyun.com/dav'),
          'https://dav.jianguoyun.com/dav/');
    });

    test('前后带引号 / 空格时要清掉', () {
      expect(WebDavConfig.normalizeUrl('  "https://dav.jianguoyun.com/dav/"  '),
          'https://dav.jianguoyun.com/dav/');
    });

    test('本来是对的就不动它（含 http 的自建服务不能升成 https）', () {
      expect(WebDavConfig.normalizeUrl('http://192.168.1.9:5005/'),
          'http://192.168.1.9:5005/');
      expect(WebDavConfig.normalizeUrl('https://app.koofr.net/dav/Koofr/'),
          'https://app.koofr.net/dav/Koofr/');
    });

    test('空的还是空的（界面据此判断要不要拦住）', () {
      expect(WebDavConfig.normalizeUrl('   '), '');
    });
  });

  group('占位模板要拦住', () {
    test('预设里那些"你的域名"没改就点测试，必须先说清楚', () {
      expect(WebDavConfig.looksLikeTemplate('https://你的域名/remote.php/dav/'),
          isTrue);
      expect(WebDavConfig.looksLikeTemplate('https://客户端专用域名/'), isTrue);
      expect(WebDavConfig.looksLikeTemplate(''), isTrue);
    });

    test('填了自己的地址就不拦', () {
      expect(WebDavConfig.looksLikeTemplate('https://dav.jianguoyun.com/dav/'),
          isFalse);
      expect(
          WebDavConfig.looksLikeTemplate('http://192.168.1.9:5005/'), isFalse);
    });
  });

  test('密码脱敏：只露头尾，短密码全遮', () {
    expect(WebDavConfig.maskPassword(''), '（未填）');
    expect(WebDavConfig.maskPassword('abcd'), '****');
    expect(WebDavConfig.maskPassword('aymtabwqyv73tcxs'), 'ay' + '****' + 'xs');
  });

  test('预设里只有坚果云要边打边转小写（Nextcloud 大小写敏感，不能转）', () {
    final jianguo = WebDavProvider.presets
        .firstWhere((WebDavProvider item) => item.name == '坚果云');
    expect(jianguo.lowercaseUsername, isTrue);
    final nextcloud = WebDavProvider.presets
        .firstWhere((WebDavProvider item) => item.name == 'Nextcloud');
    expect(nextcloud.lowercaseUsername, isFalse);
  });

  test('每个预设的地址归一化之后都是可用的形态', () {
    for (final provider in WebDavProvider.presets) {
      final url = WebDavConfig.normalizeUrl(provider.url);
      expect(url.startsWith('http'), isTrue, reason: provider.name);
      expect(url.endsWith('/'), isTrue, reason: provider.name);
      // 占位模板里的中文域名本来就解析不了（用户看到的是例子，不是地址），
      // 真正给用户用的那些必须是合法 URI。
      if (!WebDavConfig.looksLikeTemplate(url)) {
        expect(Uri.tryParse(url), isNotNull, reason: provider.name);
      }
    }
  });
}
