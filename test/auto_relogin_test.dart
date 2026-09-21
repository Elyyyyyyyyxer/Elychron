import 'package:celechron/mod/auto_relogin.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自动重登的**取舍**（v1.5.0）。
///
/// 用户原话：「加上自动重登吧。但这样会不会导致用户自己主动退登也被自动重登？」
/// —— 会，如果不加区分。所以"用户主动退登"必须有一个**明确的记号**，
/// 而且判断不能靠"手上有没有密码"：退出登录时账号密码是**故意不删**的
/// （用户要求退出后仍能预填，见 rememberAccount）。
void main() {
  test('密钥库读不出来（不是主动退登）→ 自动重登', () {
    expect(
      shouldAutoRelogin(
        appThinksLoggedIn: true,
        loggedOutByUser: false,
        username: '3190100000',
        password: 'pw',
      ),
      isTrue,
    );
  });

  test('用户主动退登 → 绝不自动重登（哪怕账号密码都还在）', () {
    expect(
      shouldAutoRelogin(
        appThinksLoggedIn: true,
        loggedOutByUser: true,
        username: '3190100000',
        password: 'pw',
      ),
      isFalse,
    );
  });

  test('App 本来就没认为自己登录着 → 不该自动重登（那是登录页的事）', () {
    expect(
      shouldAutoRelogin(
        appThinksLoggedIn: false,
        loggedOutByUser: false,
        username: '3190100000',
        password: 'pw',
      ),
      isFalse,
    );
  });

  test('账号或密码缺一个 → 不硬来（老老实实让用户重登）', () {
    expect(
      shouldAutoRelogin(
        appThinksLoggedIn: true,
        loggedOutByUser: false,
        username: '3190100000',
        password: '',
      ),
      isFalse,
    );
    expect(
      shouldAutoRelogin(
        appThinksLoggedIn: true,
        loggedOutByUser: false,
        username: '',
        password: 'pw',
      ),
      isFalse,
    );
  });
}
