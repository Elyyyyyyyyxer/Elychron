import 'package:celechron/database/database_helper.dart';
import 'package:get/get.dart';

/// ===== 自动重登（v1.5.0）=====
///
/// 背景：某些 ROM 在**覆盖安装后读系统密钥库会返回 null**（不报错），
/// 于是 App 以为自己登录着、却没有账号密码 → 刷新全失败 → 用户看到"掉登录"。
/// 代码里原来只是**让用户手动重登**（main.dart 里那段注释就是这条）。
///
/// 用户要求（2026-09-21）：自动重登，**但不能把"用户主动退出登录"也自动登回去**。
///
/// 所以加一个**明确的记号** [kUserLoggedOutKey]：
/// - 用户主动点「退出登录」→ 写上它 → **绝不自动重登**（否则用户刚退出又被登回去，那才是 bug）
/// - 用户登录成功 → 擦掉它
/// - 密钥库读不出来、但这个记号不在 → 用数据库里那份副本自动重登一次
///
/// 注意账号密码本身**退出登录时不删**（见 mod/database_mod.dart 的 rememberAccount：
/// 用户要求"退出后仍能预填"），所以判断"能不能自动重登"必须靠这个记号，
/// 而不能靠"手上有没有密码"。
const String kUserLoggedOutKey = 'mod_user_logged_out';

/// 纯函数：**要不要**自动重登（有单测）
///
/// 四个条件缺一不可：
/// - [appThinksLoggedIn]：App 认为自己登录着（否则本来就该在登录页）
/// - [loggedOutByUser]：用户**没有**主动退登
/// - 账号、密码都还在手上（来自 rememberedAccount，密钥库读不到时会退回数据库副本）
bool shouldAutoRelogin({
  required bool appThinksLoggedIn,
  required bool loggedOutByUser,
  required String username,
  required String password,
}) =>
    appThinksLoggedIn &&
    !loggedOutByUser &&
    username.isNotEmpty &&
    password.isNotEmpty;

/// 读 / 写"用户主动退登"记号
extension AutoReloginStore on DatabaseHelper {
  bool get userLoggedOutByChoice => optionsBox.get(kUserLoggedOutKey) == true;

  Future<void> setUserLoggedOut(bool value) async {
    try {
      if (value) {
        await optionsBox.put(kUserLoggedOutKey, true);
      } else {
        await optionsBox.delete(kUserLoggedOutKey);
      }
    } catch (_) {}
  }
}
