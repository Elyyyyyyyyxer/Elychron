/// 登录是否算成功 —— 只看**统一身份认证**那一步。
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
/// 原来的判据是「6 项全为 null 才算登录成功」。后果是**任何一个子站抽风都会让人登不进来**——
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

  /// 这条错误是不是「登录态本身出问题了」（而不是某个模块单独抽风）。
  ///
  /// 用来判断界面上该不该把「已登录」改成「登录已失效」：
  /// 用户反馈过"软件保持着登录状态，但实际上已经连不上了"，
  /// 所以只要错误里出现认证/会话相关字样，就认为登录态不可信。
  static bool looksLikeSessionProblem(String message) {
    final lower = message.toLowerCase();
    for (final keyword in _sessionProblemKeywords) {
      if (lower.contains(keyword)) return true;
    }
    return false;
  }

  static const List<String> _sessionProblemKeywords = <String>[
    '未登录',
    '需要登录',
    '登录已失效',
    '登录态',
    '登录过期',
    '重新登录',
    'ticket',
    'cas',
    '统一身份认证',
    '身份认证',
    '用户名或密码',
    '账号或密码',
    'unauthorized',
    '401',
  ];
}
