import 'package:celechron/mod/library_web_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('图书馆 CAS 的旧 HTTP 登录跳转升级 HTTPS 并保留 service', () {
    final source = Uri.parse(
        'http://zjuam.zju.edu.cn/cas/login?service=https%3A%2F%2Fbooking.lib.zju.edu.cn%2Fapi%2Fcas%2Fcas');
    final secure = LibraryWebSession.secureCasRedirect(source);
    expect(secure?.scheme, 'https');
    expect(secure?.host, 'zjuam.zju.edu.cn');
    expect(secure?.path, '/cas/login');
    expect(secure?.query, source.query);
  });

  test('服务器显式返回 80 端口时使用 HTTPS 默认 443', () {
    final source = Uri.parse('http://zjuam.zju.edu.cn:80/cas/login');
    final secure = LibraryWebSession.secureCasRedirect(source);
    expect(secure?.scheme, 'https');
    expect(secure?.port, 443);
  });

  test('已经 HTTPS 和其他域名不拦截，避免认证循环', () {
    for (final url in [
      'https://zjuam.zju.edu.cn/cas/login',
      LibraryWebSession.casEntryUrl,
      LibraryWebSession.homeUrl,
      'http://zjuam.zju.edu.cn.example.com/cas/login',
    ]) {
      expect(LibraryWebSession.secureCasRedirect(Uri.parse(url)), isNull);
    }
  });
}
