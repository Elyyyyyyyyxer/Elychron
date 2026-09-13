import 'package:celechron/http/calendar_config_parser.dart';
import 'package:celechron/http/zjuServices/response_utils.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/model/session.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('academic year changes in September, not July', () {
    expect(academicYearStartFor(DateTime(2026, 7, 4)), 2025);
    expect(academicYearStartFor(DateTime(2026, 8, 31)), 2025);
    expect(academicYearStartFor(DateTime(2026, 9, 1)), 2026);
  });

  test('calendar key matches academic term', () {
    expect(calendarObjectKeyForSemester('2025-2026-2'), '2025-2026-2.json');
    expect(
      calendarConfigUriForSemester('2025-2026-2').toString(),
      'http://calendar.celechron.top/2025-2026-2.json',
    );
  });

  test('timetable plan probes the next academic year before September', () {
    final plan = timetableAcademicYearPlan(
      now: DateTime(2026, 7, 5),
      graduationYearStart: 2029,
    );

    expect(plan.normalUpperBound, 2025);
    expect(plan.probeUpperBound, 2026);
    expect(plan.yearsFrom(2024), [2024, 2025, 2026]);
    expect(plan.isProbeYear(2025), isFalse);
    expect(plan.isProbeYear(2026), isTrue);
  });

  test('timetable probe never goes beyond graduation year', () {
    final plan = timetableAcademicYearPlan(
      now: DateTime(2026, 7, 5),
      graduationYearStart: 2025,
    );

    expect(plan.normalUpperBound, 2025);
    expect(plan.probeUpperBound, 2025);
    expect(plan.yearsFrom(2024), [2024, 2025]);
    expect(plan.isProbeYear(2025), isFalse);
  });

  test('only expected unavailable probe results are ignored', () {
    expect(isExpectedTimetableProbeMiss(null), isTrue);
    expect(isExpectedTimetableProbeMiss('HTTP 404'), isTrue);
    expect(isExpectedTimetableProbeMiss('kbList 暂无数据'), isTrue);
    expect(isExpectedTimetableProbeMiss('响应正文为空'), isTrue);
    expect(isExpectedTimetableProbeMiss('缺少 kbList 数组'), isTrue);
    expect(isExpectedTimetableProbeMiss('网络连接失败'), isFalse);
    expect(isExpectedTimetableProbeMiss('登录态已失效'), isFalse);
  });

  test('future timetable session survives missing calendar fallback', () {
    final semester = Semester('2026-2027秋冬');
    final fallback = buildSafeDefaultCalendarConfig('2026-2027-1');
    applyCalendarConfig(
      fallback,
      semester,
      <DateTime, String>{},
      context: '虚构未来学期',
    );
    final session = Session.fromZdbk({
      'kcb': '虚构课程<br>虚构教学班<br>虚构教师<br>虚构教室zwf',
      'sfqd': '1',
      'xqj': 2,
      'dsz': '2',
      'xxq': '秋',
      'djj': 3,
      'skcd': 2,
    });

    semester.addSession(session, '2026-2027-1');

    expect(semester.sessions, hasLength(1));
    expect(semester.sessions.single.teacher, '虚构教师');
    expect(semester.sessions.single.location, '虚构教室');
    expect(semester.sessions.single.time, [3, 4]);
  });

  test('半学期字段缺失时用请求参数兜底（否则整张课表会被滤空）', () {
    // 教务的 xxq 并不总是给「秋/冬/春/夏」：实测会缺失或只给数字码。
    // 一旦如此，firstHalf / secondHalf 会一起留在 false，课表把它整个滤掉，
    // 现象就是「课程列表有课、课时 0.0、课表空白」。
    Map<String, dynamic> row([Object? xxq]) => {
          'kcb': '虚构课程<br>虚构教学班<br>虚构教师<br>虚构教室zwf',
          'sfqd': '1',
          'xqj': 2,
          'dsz': '2',
          if (xxq != null) 'xxq': xxq,
          'djj': 3,
          'skcd': 2,
        };

    // 1. 行内没有 xxq → 用请求参数：秋学期查询 → 上半学期
    final autumn = Session.fromZdbk(row(), requestedSeason: '1|秋');
    expect(autumn.firstHalf, isTrue);
    expect(autumn.secondHalf, isFalse);

    // 2. 冬学期查询 → 下半学期
    final winter = Session.fromZdbk(row(), requestedSeason: '1|冬');
    expect(winter.secondHalf, isTrue);
    expect(winter.firstHalf, isFalse);

    // 3. xxq 只给了数字码（读不出半学期）→ 同样回落
    final numeric = Session.fromZdbk(row('1'), requestedSeason: '2|春');
    expect(numeric.firstHalf, isTrue);
    expect(numeric.secondHalf, isFalse);

    // 4. 行内说得清楚时以它为准（不要被请求参数带偏）
    final fromRow = Session.fromZdbk(row('冬'), requestedSeason: '1|秋');
    expect(fromRow.secondHalf, isTrue);
    expect(fromRow.firstHalf, isFalse);

    // 5. 两边都没有 → 保持原样（不能凭空猜）
    final unknown = Session.fromZdbk(row());
    expect(unknown.firstHalf, isFalse);
    expect(unknown.secondHalf, isFalse);
  });

  test('兜底之后课次真的能进课表', () {
    // 这是上面那个 bug 的端到端形态：修复前这里会是空列表。
    final semester = Semester('2026-2027秋冬');
    applyCalendarConfig(
      buildSafeDefaultCalendarConfig('2026-2027-1'),
      semester,
      <DateTime, String>{},
      context: '虚构学期',
    );
    semester.addSession(
      Session.fromZdbk({
        'kcb': '虚构课程<br>虚构教学班<br>虚构教师<br>虚构教室zwf',
        'sfqd': '1',
        'xqj': 2,
        'dsz': '2',
        'djj': 3,
        'skcd': 2,
      }, requestedSeason: '1|秋'),
      '2026-2027-1',
    );

    expect(semester.firstHalfTimetable[2], hasLength(1));
    expect(semester.firstHalfSessionCount, greaterThan(0));
    expect(semester.secondHalfSessionCount, 0);
  });

  test('教务返回空课表时沿用上一次的课程安排（不清空）', () {
    // 实测故障形态：一次刷新里 8 个学期查询全部返回 0 行，App 把空的学期对象
    // 整体替换进去，课表就「凭空消失」了（课程列表还在，因为那是别的字段）。
    Semester withCourse(String name, String id) {
      final semester = Semester(name);
      applyCalendarConfig(
        buildSafeDefaultCalendarConfig(id),
        semester,
        <DateTime, String>{},
        context: '虚构学期',
      );
      semester.addSession(
        Session.fromZdbk({
          'kcb': '虚构课程<br>虚构教学班<br>虚构教师<br>虚构教室zwf',
          'sfqd': '1',
          'xqj': 2,
          'dsz': '2',
          'djj': 3,
          'skcd': 2,
        }, requestedSeason: '1|秋'),
        id,
      );
      return semester;
    }

    final previous = [withCourse('2026-2027秋冬', '2026-2027-1')];
    final incomingEmpty = [Semester('2026-2027秋冬')];

    final carried = carryOverTimetablesFrom(incomingEmpty, previous);

    expect(carried, ['2026-2027秋冬']);
    expect(incomingEmpty.single.sessions, hasLength(1));
    expect(incomingEmpty.single.firstHalfSessionCount, greaterThan(0));
  });

  test('真的没有旧数据时不会被凭空造出课表', () {
    final incoming = [Semester('2026-2027秋冬')];
    expect(carryOverTimetablesFrom(incoming, [Semester('2026-2027秋冬')]), isEmpty);
    expect(incoming.single.sessions, isEmpty);
  });

  test('非空的新课表照常生效，不会被旧数据顶掉', () {
    Semester withCourse(String name, String id, int initial) {
      final semester = Semester(name);
      applyCalendarConfig(
        buildSafeDefaultCalendarConfig(id),
        semester,
        <DateTime, String>{},
        context: '虚构学期',
      );
      semester.addSession(
        Session.fromZdbk({
          'kcb': '虚构课程<br>虚构教学班<br>虚构教师<br>虚构教室zwf',
          'sfqd': '1',
          'xqj': 2,
          'dsz': '2',
          'djj': initial,
          'skcd': 2,
        }, requestedSeason: '1|秋'),
        id,
      );
      return semester;
    }

    final previous = [withCourse('2026-2027秋冬', '2026-2027-1', 3)];
    final incoming = [withCourse('2026-2027秋冬', '2026-2027-1', 5)];

    expect(carryOverTimetablesFrom(incoming, previous), isEmpty);
    expect(incoming.single.sessions, hasLength(1));
    expect(incoming.single.sessions.single.time, [5, 6]);
  });

  test('diagnostic text removes credentials and URL query values', () {
    final sanitized = DiagnosticLogService.sanitizeForDiagnostic(
      'password=secret | Cookie: session=abc | '
      'https://identity.zju.edu.cn/cas/login?ticket=ST-secret '
      '| student=3201234567',
    );
    expect(sanitized, isNot(contains('secret')));
    expect(sanitized, isNot(contains('session=abc')));
    expect(sanitized, isNot(contains('3201234567')));
    expect(sanitized, contains('/cas/login'));
  });

  test('response summary reports structure without business response values',
      () {
    final summary = responseSummary('''
      {
        "success": true,
        "name": "张三",
        "account": "1234567890",
        "balance": 88.50,
        "grade": 95,
        "courseName": "高等数学",
        "data": [{"examName": "期末考试"}]
      }
    ''');

    expect(summary, contains('JSON对象'));
    expect(summary, contains('字段数=7'));
    expect(summary, contains('常见字段=success,data'));
    for (final privateValue in [
      '张三',
      '1234567890',
      '88.50',
      '95',
      '高等数学',
      '期末考试'
    ]) {
      expect(summary, isNot(contains(privateValue)));
    }
  });

  test('diagnostic sanitizer removes structured personal fields', () {
    final sanitized = DiagnosticLogService.sanitizeForDiagnostic(
      '{"name":"张三","balance":88.5,"grade":95,'
      '"courseName":"高等数学"} | 姓名：李四 | 校园卡账户：12345678',
    );

    for (final privateValue in ['张三', '88.5', '95', '高等数学', '李四', '12345678']) {
      expect(sanitized, isNot(contains(privateValue)));
    }
    expect(sanitized, contains('<已隐藏>'));
  });
}
