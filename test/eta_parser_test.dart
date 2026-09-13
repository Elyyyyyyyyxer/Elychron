import 'package:celechron/http/zjuServices/eta.dart';
import 'package:celechron/model/semester.dart';
import 'package:flutter_test/flutter_test.dart';

/// 智慧研工（eta）课表解析。
///
/// 这段 JSON 是实测抓到并裁掉个人信息的形状：
/// `data.kbList` 按节次分组，每组是若干条安排，`ke` 里是课程明细。
Map<String, dynamic> etaPayload(List<Map<String, dynamic>> entries) => {
      'msg': 'success',
      'code': 0,
      'data': {
        'kbList': {
          for (var i = 0; i < entries.length; i++) '${i + 1}': [entries[i]],
        },
        'sjkc': [
          {'SJKCMC': '军训(虚构)-秋'},
        ],
      },
    };

Map<String, dynamic> entry({
  Object? xqj = 1,
  Object? xxq = '秋冬',
  Object? ksj = 6,
  Object? ks = 1,
  Object? sfqd = 1,
  Object? dsz = 'all',
  Object? name = '普通化学（H）',
  Object? teacher = '王勇',
  Object? location = '紫金港东1B-302',
  Object? code = '(2026-2027-1)-CHEM1002GH-0094016-1',
}) =>
    {
      'xqj': xqj,
      'xxq': xxq,
      'ksj': ksj,
      'ks': ks,
      'sfqd': sfqd,
      'dsz': dsz,
      'ke': [
        {
          'kcmc': name,
          'sksj': '秋冬{第1-8周|1节/周}',
          'rkjs': teacher,
          'jsmc': location,
          'kcdm': code,
        }
      ],
    };

void main() {
  test('把一条 eta 记录映射成课次（周几、节次、教师、教室）', () {
    final sessions = parseEtaTimetable(etaPayload([entry()]));

    expect(sessions, hasLength(1));
    final session = sessions.single;
    expect(session.name, '普通化学（H）');
    expect(session.teacher, '王勇');
    expect(session.location, '紫金港东1B-302');
    expect(session.dayOfWeek, 1);
    expect(session.time, [6]);
    expect(session.confirmed, isTrue);
  });

  test('节数决定占用哪几节', () {
    final sessions = parseEtaTimetable(etaPayload([entry(ksj: 3, ks: 3)]));
    expect(sessions.single.time, [3, 4, 5]);
  });

  test('半学期：秋冬两边都上，只写秋/冬时按各自的半边归类', () {
    final all = parseEtaTimetable(etaPayload([entry(xxq: '秋冬')])).single;
    expect(all.firstHalf, isTrue);
    expect(all.secondHalf, isTrue);

    final autumn = parseEtaTimetable(etaPayload([entry(xxq: '秋')])).single;
    expect(autumn.firstHalf, isTrue);
    expect(autumn.secondHalf, isFalse);

    final winter = parseEtaTimetable(etaPayload([entry(xxq: '冬')])).single;
    expect(winter.firstHalf, isFalse);
    expect(winter.secondHalf, isTrue);
  });

  test('半学期字段缺失时两边都算 —— 宁可显示，也不静默消失', () {
    final session = parseEtaTimetable(etaPayload([entry(xxq: null)])).single;
    expect(session.firstHalf, isTrue);
    expect(session.secondHalf, isTrue);
  });

  test('单双周：all 全上、single 只单周、double 只双周', () {
    final all = parseEtaTimetable(etaPayload([entry(dsz: 'all')])).single;
    expect(all.oddWeek, isTrue);
    expect(all.evenWeek, isTrue);

    final single = parseEtaTimetable(etaPayload([entry(dsz: 'single')])).single;
    expect(single.oddWeek, isTrue);
    expect(single.evenWeek, isFalse);

    final double = parseEtaTimetable(etaPayload([entry(dsz: 'double')])).single;
    expect(double.oddWeek, isFalse);
    expect(double.evenWeek, isTrue);
  });

  test('缺关键字段的记录被跳过，不会抛异常', () {
    final payload = etaPayload([
      entry(),
      entry(name: '  '), // 没有课名
      entry(xqj: null), // 没有星期
      entry(ksj: null), // 没有起始节次
    ]);
    expect(parseEtaTimetable(payload), hasLength(1));
  });

  test('空课表与异常响应都返回空列表', () {
    expect(parseEtaTimetable({'code': 0, 'data': {'kbList': {}}}), isEmpty);
    expect(parseEtaTimetable({'code': 0, 'data': null}), isEmpty);
    expect(parseEtaTimetable({'code': 1, 'msg': 'error'}), isEmpty);
  });

  test('课程名的英文括号统一成中文括号', () {
    final session =
        parseEtaTimetable(etaPayload([entry(name: '高等数学(H)')])).single;
    expect(session.name, '高等数学（H）');
  });

  test('落进学期对象后能真的显示在课表上', () {
    // 端到端形态：解析 → 入库 → firstHalfTimetable 里有它。
    final semester = Semester('2026-2027秋冬');
    final sessions =
        parseEtaTimetable(etaPayload([entry(xqj: 2), entry(xqj: 3, ksj: 1)]));
    for (final session in sessions) {
      semester.addSession(session, '2026-2027-1');
    }

    expect(semester.sessions, hasLength(2));
    expect(semester.firstHalfTimetable[2], hasLength(1));
    expect(semester.firstHalfTimetable[3], hasLength(1));
    expect(semester.firstHalfSessionCount, greaterThan(0));
  });
}
