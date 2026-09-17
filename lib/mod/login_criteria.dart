/// 登录是否算成功， 只看**统一身份认证**那一步。
///
/// ## 为什么不能要求"全部子站都成功"
///
/// 子站登录返回的是一个列表：
///
/// ```
/// [0] 统一身份认证（CAS）  ← 身份本身
/// [1] 学在浙大
/// [2] 教务网
/// [3] 素质拓展
/// [4] 研究生院
/// [5] 智慧研工
/// ```
///
/// 原来的判据是6 项全为 null 才算登录成功。后果是**任何一个子站抽风都会让人登不进来**，
/// 实测就遇到过教务网（zdbk）故障导致第一次登录直接失败，而统一身份认证其实已经通过、
/// 其它模块也都能用。
///
/// 现在的判据：**身份认证成功就算登录成功**；子站失败降级为"部分模块暂不可用"，
/// 交给诊断报告与重试去处理（课表还有智慧研工兜底、缓存也不会被清空）。
class LoginCriteria {
  LoginCriteria._();

  /// 统一身份认证在返回列表里的下标
  static const int ssoIndex = 0;

  /// 身份认证明细对应的模块名，用于提示
  static const List<String> moduleNames = <String>[
    '统一身份认证',
    '学在浙大',
    '教务网',
    '素质拓展平台',
    '研究生院网',
    '智慧研工',
  ];

  /// 登录是否算成功（纯函数，便于单测）
  static bool succeeded(List<String?> messages) {
    if (messages.isEmpty) return false;
    return messages[ssoIndex] == null;
  }

  /// 本次登录失败/降级的模块消息（已剔除空项）
  static List<String> issues(List<String?> messages) {
    final result = <String>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message == null || message.trim().isEmpty) continue;
      result.add(message);
    }
    return result;
  }

  /// 身份已通过、但有子站失败时，给用户看的一句话（没有失败则返回空串）
  static String degradedHint(List<String?> messages) {
    final failed = <String>[];
    for (var i = 0; i < messages.length; i++) {
      if (i == ssoIndex) continue;
      final message = messages[i];
      if (message == null || message.trim().isEmpty) continue;
      failed.add(i < moduleNames.length ? moduleNames[i] : '模块 $i');
    }
    if (failed.isEmpty) return '';
    return '已登录，但${failed.join('、')}暂时连不上。'
        '这些模块的数据稍后下拉刷新会自动重试，其它功能不受影响。';
  }

  /// 这条错误是不是**用户自己的登录态**出问题了。
  ///
  /// ⚠️ **判据必须保守，宁可漏报也不要误报**。第一版的教训：
  /// 当时扫的是未登录 / cas / 401 / 身份认证这类词，结果设置页老是显示
  /// 登录已失效，但用户其实好好的， 因为
  ///
  /// - `学在浙大：未登录`、`智慧研工未登录或会话已失效` 是**模块各自的会话**
  ///   （各子站有自己的登录，设计上就是可容忍的降级，见 `isDegradedRefreshText`），
  ///   而且 `未登录` 还在 `_commonRetryableMessages` 里， 框架自己都把它当瞬时问题重试；
  /// - `cas` 是**子串**，而错误详情里几乎都带 URL（`https://zjuam.zju.edu.cn/cas/login`）；
  /// - `401` 同理，任何数字里带 401 的内容都会命中。
  ///
  /// 所以现在只认**措辞明确、且只会出现在认证语境里**的短语。
  /// 判断"要不要显示登录已失效"时，还应该配合
  /// `isDegradedRefreshText`（可容忍降级一律排除）。
  static bool looksLikeSessionProblem(String message) {
    final lower = message.toLowerCase();
    for (final keyword in _sessionProblemKeywords) {
      if (lower.contains(keyword)) return true;
    }
    return false;
  }

  /// 只保留"明确指认证/凭据本身失效"的短语。
  ///
  /// 不要往这里加 `cas` / `401` / `未登录` / `身份认证` 这类宽泛词，
  /// 它们都会把"某个模块自己的会话问题"误判成"用户登录失效"。
  static const List<String> _sessionProblemKeywords = <String>[
    '无法登录统一身份认证',
    '用户名或密码',
    '账号或密码',
    '登录已失效',
    '登录态已失效',
    '登录态失效',
    '登录态已过期',
    '登录已过期',
    '登录过期',
    '请重新登录',
    '需要重新登录',
    // ⚠️ 别加"会话已失效"这类词：智慧研工模块自己的消息就长这样
    //    （'智慧研工未登录或会话已失效'），加了会重新变成误报。
    'cas ticket', // "未获得 CAS ticket"：认证票据拿不到，确实是自己登录的问题
    'unauthorized',
  ];
}
