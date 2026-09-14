import 'package:celechron/mod/login_criteria.dart';
import 'package:flutter_test/flutter_test.dart';

/// 登录判据：**身份认证成功就算登录成功**，子站失败只降级不阻断。
///
/// 这里锁的是一个真实故障：教务网（zdbk）故障时，原来的「全部子站都成功」判据
/// 会让用户连 App 都进不去 —— 哪怕统一身份认证已经通过、其它模块也都能用。
void main() {
  test('全部成功 → 登录成功，无降级提示', () {
    final r = <String?>[null, null, null, null, null, null];
    expect(LoginCriteria.succeeded(r), isTrue);
    expect(LoginCriteria.issues(r), isEmpty);
    expect(LoginCriteria.degradedHint(r), '');
  });

  test('教务网失败（身份已过）→ 仍然算登录成功', () {
    final r = <String?>[null, null, '无法登录教务网：连接被重置', null, null, null];
    expect(LoginCriteria.succeeded(r), isTrue);
    expect(LoginCriteria.issues(r).length, 1);
    expect(LoginCriteria.degradedHint(r), contains('教务网'));
    expect(LoginCriteria.degradedHint(r), contains('已登录'));
  });

  test('多个子站失败 → 提示里逐个点名', () {
    final r = <String?>[null, '无法登录学在浙大', '无法登录教务网', null, null, null];
    final hint = LoginCriteria.degradedHint(r);
    expect(hint, contains('学在浙大'));
    expect(hint, contains('教务网'));
  });

  test('统一身份认证失败 → 登录失败（这才是真的登不进去）', () {
    final r = <String?>['无法登录统一身份认证', null, null, null, null, null];
    expect(LoginCriteria.succeeded(r), isFalse);
  });

  test('空列表 → 不算成功（防御式）', () {
    expect(LoginCriteria.succeeded(<String?>[]), isFalse);
  });

  test('空白字符串不算失败（接口偶发返回空串）', () {
    final r = <String?>[null, '  ', '', null, null, null];
    expect(LoginCriteria.succeeded(r), isTrue);
    expect(LoginCriteria.degradedHint(r), '');
  });

  test('未知下标的失败也不会崩，只报「模块 N」', () {
    final r = <String?>[null, null, null, null, null, null, '未来新增的模块挂了'];
    expect(LoginCriteria.succeeded(r), isTrue);
    expect(LoginCriteria.degradedHint(r), contains('模块 6'));
  });

  test('模块名表覆盖到实际用到的下标', () {
    expect(LoginCriteria.moduleNames.length, greaterThanOrEqualTo(6));
    expect(LoginCriteria.moduleNames[LoginCriteria.ssoIndex], '统一身份认证');
  });
}
