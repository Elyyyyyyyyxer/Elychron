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

  // ===== 登录态失效识别 =====
  //
  // 决定界面上显示「已登录」还是「登录已失效」。用户反馈过
  // 「软件保持着登录状态，但实际上已经连不上了」，所以要既能认出认证类问题，
  // 又**不能**把某个模块单独抽风误判成登录失效。

  test('认证/会话类错误会被认出来', () {
    expect(LoginCriteria.looksLikeSessionProblem('无法登录统一身份认证'), isTrue);
    expect(LoginCriteria.looksLikeSessionProblem('未获得 CAS ticket'), isTrue);
    expect(LoginCriteria.looksLikeSessionProblem('登录已失效，请重新登录'), isTrue);
    expect(LoginCriteria.looksLikeSessionProblem('登录态已过期'), isTrue);
    expect(LoginCriteria.looksLikeSessionProblem('用户名或密码错误'), isTrue);
    expect(LoginCriteria.looksLikeSessionProblem('HTTP 401 Unauthorized'), isTrue);
  });

  test('普通模块抽风不会被误判成登录失效', () {
    expect(LoginCriteria.looksLikeSessionProblem('教务网请求超时'), isFalse);
    expect(LoginCriteria.looksLikeSessionProblem('素质拓展平台暂时不可用'), isFalse);
    expect(LoginCriteria.looksLikeSessionProblem('SocketException: 连接被重置'), isFalse);
    expect(LoginCriteria.looksLikeSessionProblem('接口返回 0 行'), isFalse);
  });

  // ===== 回归：第一版判据太宽，设置页老是误报「登录已失效」 =====
  //
  // 下面是**真实消息原文**（来自代码，不是编的）。它们说的都是"某个子站自己的会话"，
  // 设计上属于可容忍降级，**绝不能**让整机显示"登录已失效"。
  group('误报回归：模块自己的会话问题不算用户登录失效', () {
    test('学在浙大未登录（模块自己的会话）', () {
      expect(LoginCriteria.looksLikeSessionProblem('学在浙大：未登录'), isFalse);
    });

    test('智慧研工未登录或会话已失效（模块自己的会话）', () {
      expect(
        LoginCriteria.looksLikeSessionProblem('智慧研工未登录或会话已失效'),
        isFalse,
      );
    });

    test('教务网直接抛"未登录"', () {
      expect(LoginCriteria.looksLikeSessionProblem('未登录'), isFalse);
    });

    test('错误详情里带 CAS 登录页 URL 不算（这是第一版误报的主因）', () {
      const withUrl =
          '无法登录教务网：连接被重置（POST https://zjuam.zju.edu.cn/cas/login → 500）';
      expect(LoginCriteria.looksLikeSessionProblem(withUrl), isFalse);
    });

    test('消息里出现 401 这类数字不算（短子串太容易误命中）', () {
      expect(LoginCriteria.looksLikeSessionProblem('接口返回 401 行数据'), isFalse);
      expect(LoginCriteria.looksLikeSessionProblem('课程号 0401 不存在'), isFalse);
    });

    test('提到"统一身份认证"但只是描述过程，不算失效', () {
      expect(
        LoginCriteria.looksLikeSessionProblem('已通过统一身份认证，正在获取课表'),
        isFalse,
      );
    });
  });
}
