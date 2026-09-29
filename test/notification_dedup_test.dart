import 'package:celechron/worker/notification_dedup.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这些断言钉的是"同一句话绝不重复发"这道闸。
///
/// 为什么值得测：它守的是用户的原话「一天会给我推送很多次那个通知」。
/// 每个用例用不同的 key，互不干扰（文件就在系统临时目录里）。
void main() {
  test('没记过就是没发过', () async {
    expect(await NotificationDedup.everSent('t-missing', 'x'), isFalse);
    expect(await NotificationDedup.read('t-missing'), isNull);
  });

  test('记过之后就永远算发过', () async {
    await NotificationDedup.markSent('t-ever', 'intro-v1');
    expect(await NotificationDedup.everSent('t-ever', 'intro-v1'), isTrue);
    expect(await NotificationDedup.everSent('t-ever', 'intro-v2'), isFalse);
  });

  test('窗口期内算发过，指纹不同不算', () async {
    await NotificationDedup.markSent('t-window', 'gpa=4.50|count=28');
    expect(
        await NotificationDedup.sentRecently(
            't-window', 'gpa=4.50|count=28', const Duration(hours: 6)),
        isTrue);
    expect(
        await NotificationDedup.sentRecently(
            't-window', 'gpa=4.60|count=29', const Duration(hours: 6)),
        isFalse);
  });

  test('超过窗口期就不算发过（真出新分数要能提醒）', () async {
    await NotificationDedup.markSent('t-expire', 'same');
    final later = DateTime.now().add(const Duration(hours: 7));
    expect(
        await NotificationDedup.sentRecently(
            't-expire', 'same', const Duration(hours: 6),
            now: later),
        isFalse);
  });

  test('时钟被往后调过时宁可少发一次', () async {
    await NotificationDedup.markSent('t-clock', 'same');
    final earlier = DateTime.now().subtract(const Duration(days: 2));
    expect(
        await NotificationDedup.sentRecently(
            't-clock', 'same', const Duration(hours: 6),
            now: earlier),
        isTrue);
  });

  test('DDL 的已提醒列表能原样存取', () async {
    await NotificationDedup.write(
        't-ddl', <String, dynamic>{'ids': <String>['a', 'b']});
    final record = await NotificationDedup.read('t-ddl');
    expect(record?['ids'], <String>['a', 'b']);
  });
}
