import 'package:celechron/http/calendar_bundled_config.dart';
import 'package:celechron/http/calendar_config_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// 校历的两块**纯逻辑 + 资源**测试（2026-09-17 用户拍板后加的）。
///
/// 背景：校历来自上游第三方站（明文 HTTP，实测长期不稳），用户拍板：
/// **随包内置一份 + 每周试一次远程 + 有差异按新的来**。
/// 这里保证：内置的那几份真的在包里、真的能解析、以及"每周一次"的节流判断是对的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('随包内置的校历', () {
    test('每一份都能真的读出来（文件忘了放 / 名字改了会红）', () async {
      expect(BundledCalendarConfig.bundledSemesters, isNotEmpty);
      for (final semesterId in BundledCalendarConfig.bundledSemesters) {
        final text = await BundledCalendarConfig.load(semesterId);
        expect(text, isNotNull,
            reason: 'assets/calendar/$semesterId.json 没打进包里');
        expect(text!.trim(), isNotEmpty, reason: semesterId);
      }
    });

    test('内容能通过校验（startEnd 四个日期 + sessionTime ≥15 节）', () async {
      for (final semesterId in BundledCalendarConfig.bundledSemesters) {
        final text = (await BundledCalendarConfig.load(semesterId))!;
        final config = decodeAndValidateCalendarConfig(
          text,
          context: '内置校历 $semesterId',
        );
        expect((config['startEnd'] as List).length, 4, reason: semesterId);
        expect((config['sessionTime'] as List).length, greaterThanOrEqualTo(15),
            reason: semesterId);
      }
    });

    test('2026-2027 秋冬那份就是这学期（9/14 开学、11/9 进下半学期）', () async {
      final text = (await BundledCalendarConfig.load('2026-2027-1'))!;
      final config = decodeAndValidateCalendarConfig(text, context: '内置校历');
      final startEnd = (config['startEnd'] as List).cast<String>();
      expect(startEnd.first, '20260914');
      expect(startEnd[2], '20261109');
    });

    test('中文没乱码（曾经用错编码下载过一次，这里是护栏）', () async {
      final text = (await BundledCalendarConfig.load('2026-2027-1'))!;
      // 中秋节 / 国庆节在 holiday 里；乱码时会是「ä¸­ç§è」这种拉丁字符
      expect(text.contains('中秋'), isTrue);
      expect(text.contains('国庆'), isTrue);
    });

    test('没有内置的学期返回 null（不是抛错）', () async {
      expect(await BundledCalendarConfig.load('1999-2000-1'), isNull);
    });
  });

  group('每周才试一次远程', () {
    final now = DateTime.utc(2026, 9, 17, 12);

    test('从没试过 → 该试', () {
      expect(isCalendarRemoteUpdateDue(lastAttempt: null, now: now), isTrue);
    });

    test('刚试过 / 3 天前试过 → 不试', () {
      expect(
          isCalendarRemoteUpdateDue(
              lastAttempt: now.subtract(const Duration(hours: 1)), now: now),
          isFalse);
      expect(
          isCalendarRemoteUpdateDue(
              lastAttempt: now.subtract(const Duration(days: 3)), now: now),
          isFalse);
    });

    test('满 7 天 → 该试（边界按 >=）', () {
      expect(
          isCalendarRemoteUpdateDue(
              lastAttempt: now.subtract(const Duration(days: 7)), now: now),
          isTrue);
      expect(
          isCalendarRemoteUpdateDue(
              lastAttempt: now.subtract(const Duration(days: 8)), now: now),
          isTrue);
    });

    test('设备时钟被往回拨（上次尝试在未来）→ 不试', () {
      expect(
          isCalendarRemoteUpdateDue(
              lastAttempt: now.add(const Duration(days: 30)), now: now),
          isFalse);
    });
  });

  group('远程地址候选', () {
    test('顺序：上游 HTTPS → 上游 HTTP → Gitee 镜像 → GitHub 镜像', () {
      final uris = calendarConfigUriCandidates('2026-2027-1');
      expect(uris.length, 4);
      expect(uris[0].toString(),
          'https://calendar.celechron.top/2026-2027-1.json');
      expect(
          uris[1].toString(), 'http://calendar.celechron.top/2026-2027-1.json');
      // 镜像必须是 HTTPS，而且路径就是仓库里那份（assets/calendar/）
      expect(uris[2].scheme, 'https');
      expect(uris[2].toString(), contains('gitee.com'));
      expect(uris[2].toString(), contains('/assets/calendar/2026-2027-1.json'));
      expect(uris[3].scheme, 'https');
      expect(uris[3].toString(), contains('raw.githubusercontent.com'));
      expect(uris[3].toString(), contains('/assets/calendar/2026-2027-1.json'));
    });

    test('学期 id 不合法时直接抛（不要把脏参数带进 URL）', () {
      expect(() => calendarConfigUriCandidates('2026秋'), throwsFormatException);
    });
  });
}
