import 'package:celechron/worker/background_app_refresh.dart';
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

  /// 「成绩推送已开启」那条开场白：三道闸（Hive / 文件 / 密钥库）任意一道
  /// 说"说过了"就不许再说。用户原话：「始终时不时给我推"成绩推送已开启"」——
  /// 当时只看文件 + 密钥库，而覆盖安装会把密钥库读空、缓存会被清，
  /// 两道闸一起丢，那条一辈子只说一次的通知就复活了。
  group('成绩推送开场白：三道闸', () {
    const fp = 'grade-push-intro-v1';
    bool show({
      String hive = '',
      bool file = false,
      bool storage = false,
    }) =>
        shouldShowGradePushIntro(
          fingerprint: fp,
          hiveMark: hive,
          saidInFile: file,
          saidInStorage: storage,
        );

    test('三处都没记过才说', () {
      expect(show(), isTrue);
    });

    test('Hive 记过就永远不说（哪怕文件、密钥库都丢了）', () {
      expect(show(hive: fp), isFalse);
      expect(show(hive: fp, file: false, storage: false), isFalse);
    });

    test('Hive 没记但文件记过 → 不说（老版本留下来的记录也算）', () {
      expect(show(file: true), isFalse);
    });

    test('Hive 没记但密钥库记过 → 不说', () {
      expect(show(storage: true), isFalse);
    });

    test('指纹换代才重新允许说（防止误伤：换了文案要能再说一次）', () {
      expect(show(hive: 'grade-push-intro-v0'), isTrue);
    });
  });
}
