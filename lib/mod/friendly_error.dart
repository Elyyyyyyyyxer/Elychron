import 'package:celechron/http/zjuServices/exceptions.dart';

/// 把底层异常压成**一句人话**，供界面显示。
///
/// ## 为什么要做这个
///
/// 用户反馈：「请简化所有的用户容易看到的报错提示，不然看到一老长串非常吓人……
/// 统一认证账号登录时如果输错了会产生很长很长的报错表。」
///
/// 原因是界面上直接把 `异常.toString()` 贴出来了，而 [ExceptionWithMessage] 的
/// toString 会拼成
/// `消息 + '\n<<<CELECHRON_ERROR_DETAIL>>>\n' + 详情`，
/// 详情里往往还有 URL、HTTP 状态、响应片段 —— 一行能撑满整屏，用户完全看不懂。
///
/// 规则很简单：**界面只给人话，细节去日志里找**（诊断与测试里能看到原文）。
/// 所以这里做三件事：
/// 1. 砍掉详情段（分隔符之后全丢）；
/// 2. 按关键词映射成常见人话（密码错、超时、连不上、服务器挂了…）；
/// 3. 兜底也截断，绝不让一行撑满屏。
class FriendlyError {
  FriendlyError._();

  /// 界面上一行最多显示这么多字
  static const int maxChars = 42;

  /// 常见故障 → 人话
  static const Map<String, List<String>> _rules = {
    '账号或密码不对，请检查后重试': [
      '用户名或密码',
      '密码错误',
      '账号或密码',
      'incorrect',
      'unauthorized',
      '401',
      '身份认证凭据无效',
    ],
    '登录状态已失效，请重新登录': [
      'ticket',
      '登录态失效',
      '未获得 cas',
      'session',
      '未登录',
    ],
    '连不上学校服务器，请检查网络后重试': [
      'socketexception',
      'failed host lookup',
      'connection refused',
      'connection reset',
      'network is unreachable',
      '连不上',
      '无法连接',
    ],
    '网络超时，请稍后重试': [
      'timeout',
      'timed out',
      '超时',
    ],
    '学校服务器暂时不可用，请稍后再试': [
      '503',
      '502',
      '500',
      'bad gateway',
      'service unavailable',
      '服务器繁忙',
    ],
    '服务器返回的内容看不懂，可能是学校接口变了': [
      'formatexception',
      'json',
      '解析失败',
      'unexpected character',
    ],
  };

  /// 取一句人话。[fallback] 是什么都没匹配上时的兜底文案。
  static String short(Object? error, {String fallback = '操作失败，请稍后重试'}) {
    final raw = _clean(error);
    if (raw.isEmpty) return fallback;
    final lower = raw.toLowerCase();
    for (final entry in _rules.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword.toLowerCase())) return entry.key;
      }
    }
    return _truncate(raw);
  }

  /// 是否属于"账号密码"这一类错误（登录页需要额外提示去检查输入）
  static bool looksLikeCredentialProblem(Object? error) {
    final lower = _clean(error).toLowerCase();
    return _rules['账号或密码不对，请检查后重试']!
        .any((k) => lower.contains(k.toLowerCase()));
  }

  /// 砍掉详情段与多余空白，并去掉常见的异常前缀
  static String _clean(Object? error) {
    if (error == null) return '';
    var text = error.toString();
    // 1) 丢弃分隔符之后的详情（URL / 状态码 / 响应片段，用户看不懂，也没必要看）
    final markerIndex = text.indexOf(refreshErrorDetailMarker);
    if (markerIndex >= 0) text = text.substring(0, markerIndex);
    // 2) 只保留第一行（堆栈与多行细节一律不要）
    final newline = text.indexOf('\n');
    if (newline >= 0) text = text.substring(0, newline);
    // 3) 去掉异常类名与常见前缀
    text = text
        .replaceFirst(RegExp(r'^(Exception|LoginException|ExceptionWithMessage):\s*'), '')
        .replaceFirst(RegExp(r'^无法登录[^：:]*[：:]\s*'), '')
        .trim();
    return text;
  }

  static String _truncate(String text) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}…';
  }
}
