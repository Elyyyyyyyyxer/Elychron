import 'package:celechron/mod/webdav_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// 预设服务商（W3）：**把"记地址"这一步消掉** —— 用户点一下，地址就填好了。
void main() {
  test('坚果云排在第一个（国内用户最顺，也最容易拿到应用密码）', () {
    expect(WebDavProvider.presets.first.name, '坚果云');
    expect(WebDavProvider.presets.first.url, 'https://dav.jianguoyun.com/dav/');
  });

  test('每个预设都要有地址、用户名提示、应用密码提示（界面直接显示，不能空）', () {
    for (final provider in WebDavProvider.presets) {
      expect(provider.name, isNotEmpty);
      expect(provider.url, isNotEmpty);
      expect(provider.usernameHint, isNotEmpty);
      expect(provider.passwordHint, isNotEmpty);
    }
  });

  test('能认出用户填的地址是哪一家（界面显示名字而不是一串 URL）', () {
    expect(
      WebDavProvider.match('https://dav.jianguoyun.com/dav/')?.name,
      '坚果云',
    );
    expect(
      WebDavProvider.match('https://app.koofr.net/dav/Koofr/')?.name,
      'Koofr',
    );
    expect(WebDavProvider.match('http://192.168.1.9:5244/dav/'), isNull);
    expect(WebDavProvider.match(''), isNull);
  });

  test('坚果云的提示里必须写清"要小写"（实测大写会 401）', () {
    final nutstore = WebDavProvider.presets.first;
    expect(nutstore.usernameHint.contains('小写'), isTrue);
    expect(nutstore.passwordPageUrl, isNotEmpty);
  });
}
