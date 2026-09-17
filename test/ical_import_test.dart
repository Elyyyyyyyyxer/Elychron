import 'package:celechron/mod/ical_import.dart';
import 'package:celechron/model/task.dart';
import 'package:flutter_test/flutter_test.dart';

/// iCal（.ics）导入：解析 + 类型映射 + 去重。
///
/// 用真实形态的 .ics 文本当输入（折叠行、TZID、UTC 的 Z、全天 VALUE=DATE、
/// 转义字符），因为这些细节正是最容易写错的地方。
void main() {
  const basic = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//CN
BEGIN:VEVENT
UID:event-1@example.com
SUMMARY:新生开学典礼
DTSTART;TZID=Asia/Shanghai:20260914T174500
DTEND;TZID=Asia/Shanghai:20260914T203000
LOCATION:紫云篮球场
DESCRIPTION:请统一穿白色院衫
END:VEVENT
END:VCALENDAR
''';

  test('解析基本事件：标题/时间/地点/描述', () {
    final events = IcalImporter.parseIcal(basic);
    expect(events.length, 1);
    final e = events.first;
    expect(e.summary, '新生开学典礼');
    expect(e.location, '紫云篮球场');
    expect(e.description, '请统一穿白色院衫');
    expect(e.start, DateTime(2026, 9, 14, 17, 45));
    expect(e.end, DateTime(2026, 9, 14, 20, 30));
  });

  test('有起止 → 活动型', () {
    final task = IcalImporter.toTask(IcalImporter.parseIcal(basic).first);
    expect(task.type, TaskType.fixed);
    expect(task.startTime, DateTime(2026, 9, 14, 17, 45));
    expect(task.endTime, DateTime(2026, 9, 14, 20, 30));
  });

  test('只有 DTSTART → 提醒型（单时刻）', () {
    const ics = '''
BEGIN:VEVENT
UID:a2
SUMMARY:去取快递
DTSTART:20260914T090000
END:VEVENT''';
    final task = IcalImporter.toTask(IcalImporter.parseIcal(ics).first);
    expect(task.type, TaskType.remind);
    expect(task.endTime, DateTime(2026, 9, 14, 9, 0));
  });

  test('只有 DTEND → 截止型', () {
    const ics = '''
BEGIN:VEVENT
UID:a3
SUMMARY:交实验报告
DTEND:20260918T170000
END:VEVENT''';
    final task = IcalImporter.toTask(IcalImporter.parseIcal(ics).first);
    expect(task.type, TaskType.deadline);
    expect(task.endTime, DateTime(2026, 9, 18, 17, 0));
  });

  test('全天事件（VALUE=DATE）按当天 23:59', () {
    const ics = '''
BEGIN:VEVENT
UID:a4
SUMMARY:国庆假期
DTSTART;VALUE=DATE:20261001
DTEND;VALUE=DATE:20261008
END:VEVENT''';
    final task = IcalImporter.toTask(IcalImporter.parseIcal(ics).first);
    expect(task.startTime, DateTime(2026, 10, 1, 23, 59));
    expect(task.endTime, DateTime(2026, 10, 8, 23, 59));
  });

  test('UTC 时间（Z 结尾）会换算成本地时间', () {
    const ics = '''
BEGIN:VEVENT
UID:a5
SUMMARY:线上会议
DTSTART:20260914T053000Z
DTEND:20260914T063000Z
END:VEVENT''';
    final task = IcalImporter.toTask(IcalImporter.parseIcal(ics).first);
    final expected = DateTime.utc(2026, 9, 14, 5, 30).toLocal();
    expect(task.startTime, expected);
  });

  test('折叠行（续行以空格开头）会被拼回一行', () {
    const ics = 'BEGIN:VEVENT\n'
        'UID:a6\n'
        'SUMMARY:这是一个很长的标题，长到 iCal 会把它\n'
        ' 折成两行\n'
        'DTSTART:20260914T100000\n'
        'END:VEVENT';
    expect(
        IcalImporter.parseIcal(ics).first.summary, '这是一个很长的标题，长到 iCal 会把它折成两行');
  });

  test('转义字符还原（\\, \\; \\n）', () {
    const ics = 'BEGIN:VEVENT\n'
        'UID:a7\n'
        'SUMMARY:买牛奶\\, 面包\n'
        'DESCRIPTION:第一行\\n第二行\n'
        'DTSTART:20260914T100000\n'
        'END:VEVENT';
    final e = IcalImporter.parseIcal(ics).first;
    expect(e.summary, '买牛奶, 面包');
    expect(e.description, '第一行\n第二行');
  });

  test('一个文件里多条事件都能解析', () {
    final ics = '$basic\n'
        'BEGIN:VEVENT\n'
        'UID:event-2@example.com\n'
        'SUMMARY:另一件事\n'
        'DTEND:20260915T120000\n'
        'END:VEVENT';
    expect(IcalImporter.parseIcal(ics).length, 2);
  });

  test('没有标题也没有时间的事件会被丢掉', () {
    const ics = 'BEGIN:VEVENT\nUID:empty\nEND:VEVENT';
    expect(IcalImporter.parseIcal(ics), isEmpty);
  });

  test('重复导入同一个文件：已存在的按 uid 跳过，不产生重复待办', () {
    final events = IcalImporter.parseIcal(basic);
    final uid = IcalImporter.localUidFor(events.first);

    final first = IcalImporter.plan(events, existingUids: <String>{});
    expect(first.tasks.length, 1);
    expect(first.skipped, isEmpty);

    final second = IcalImporter.plan(events, existingUids: <String>{uid});
    expect(second.tasks, isEmpty);
    expect(second.skipped.length, 1);
    expect(second.summary, contains('跳过'));
  });

  test('同一个文件内部重复的事件也只导入一次', () {
    final ics = '$basic\n$basic';
    final events = IcalImporter.parseIcal(ics);
    final plan = IcalImporter.plan(events, existingUids: <String>{});
    expect(plan.tasks.length, 1);
  });

  test('uid 稳定：同一事件多次生成的 uid 一致', () {
    final a = IcalImporter.parseIcal(basic).first;
    final b = IcalImporter.parseIcal(basic).first;
    expect(IcalImporter.localUidFor(a), IcalImporter.localUidFor(b));
    expect(
        IcalImporter.localUidFor(a).startsWith(IcalImporter.uidPrefix), isTrue);
  });

  test('没有 UID 的事件用标题+时间兜底生成 uid', () {
    const ics = '''
BEGIN:VEVENT
SUMMARY:没写 UID 的事
DTSTART:20260914T080000
END:VEVENT''';
    final e = IcalImporter.parseIcal(ics).first;
    final uid = IcalImporter.localUidFor(e);
    expect(uid.startsWith(IcalImporter.uidPrefix), isTrue);
    expect(uid.length, greaterThan(IcalImporter.uidPrefix.length));
  });

  test('备忘型事件（无时间）不提醒', () {
    const ics = '''
BEGIN:VEVENT
UID:a8
SUMMARY:记得买牙膏
END:VEVENT''';
    final task = IcalImporter.toTask(IcalImporter.parseIcal(ics).first);
    expect(task.type, TaskType.memo);
    expect(task.schedulesReminder, isFalse);
  });

  test('空文件 / 非 iCal 文本不会炸', () {
    expect(IcalImporter.parseIcal(''), isEmpty);
    expect(IcalImporter.parseIcal('这不是 iCal'), isEmpty);
  });
}
