import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/mod/friendly_error.dart';
import 'package:flutter_test/flutter_test.dart';

/// 界面报错必须**短且是人话**。
///
/// 用户原话：请简化所有的用户容易看到的报错提示，不然看到一老长串非常吓人……
/// 统一认证账号登录时如果输错了会产生很长很长的报错表。
///
/// 那些又长又吓人的文本来自 `ExceptionWithMessage.toString()`：
/// `消息 + '\n<<<CELECHRON_ERROR_DETAIL>>>\n' + 详情`（详情里有 URL、状态码、响应片段）。
void main() {
  test('砍掉详情段：分隔符之后的内容不进界面', () {
    final raw = '无法登录统一身份认证：用户名或密码错误'
        '$refreshErrorDetailMarker'
        'POST https://zjuam.zju.edu.cn/cas/login → 401，响应片段：{"code":"BAD_CREDENTIAL"}';
    final short = FriendlyError.short(raw);
    expect(short, '账号或密码不对，请检查后重试');
  });

  test('密码错/401/incorrect 都是同一句人话', () {
    expect(FriendlyError.short('用户名或密码错误'), '账号或密码不对，请检查后重试');
    expect(FriendlyError.short('HTTP 401 Unauthorized'), '账号或密码不对，请检查后重试');
    expect(FriendlyError.short('Incorrect username or password'),
        '账号或密码不对，请检查后重试');
  });

  test('连不上 / 超时 / 服务器挂 各有各的人话', () {
    expect(FriendlyError.short('SocketException: Failed host lookup'),
        '连不上学校服务器，请检查网络后重试');
    expect(FriendlyError.short('TimeoutException after 0:00:08'), '网络超时，请稍后重试');
    expect(FriendlyError.short('HTTP 503 Service Unavailable'),
        '学校服务器暂时不可用，请稍后再试');
  });

  test('登录态失效单独一句（提示重新登录）', () {
    expect(FriendlyError.short('未获得 CAS ticket'), '登录状态已失效，请重新登录');
  });

  test('不认识的错误也会被截短，绝不撑满屏', () {
    final long = '某个没见过的错误：' + ('很长的细节' * 20);
    final short = FriendlyError.short(long);
    expect(short.length, lessThanOrEqualTo(FriendlyError.maxChars + 1));
    expect(short.endsWith('…'), isTrue);
  });

  test('只取第一行，堆栈不会漏进界面', () {
    final short = FriendlyError.short('连接失败\n#0 foo\n#1 bar');
    expect(short.contains('#0'), isFalse);
  });

  test('null / 空串走兜底文案', () {
    expect(FriendlyError.short(null), '操作失败，请稍后重试');
    expect(FriendlyError.short(''), '操作失败，请稍后重试');
    expect(FriendlyError.short(null, fallback: '自定义兜底'), '自定义兜底');
  });

  test('能识别出"是账号密码问题"（登录页据此给引导）', () {
    expect(FriendlyError.looksLikeCredentialProblem('用户名或密码错误'), isTrue);
    expect(
        FriendlyError.looksLikeCredentialProblem('SocketException'), isFalse);
  });

  test('异常类名前缀会被去掉', () {
    final short = FriendlyError.short('Exception: 网络超时');
    expect(short, '网络超时，请稍后重试');
  });
}
