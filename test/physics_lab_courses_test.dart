import 'dart:convert';
import 'package:celechron/http/calendar_bundled_config.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/session.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/exam.dart';
import 'package:celechron/mod/physics_lab_courses.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture({String dates = '2026-10-10'}) => {
      'owner': 'fixture-account',
      'rows': [
        {
          'term_id': 1,
          'course_id': 2,
          'course_student_lab_id': 3,
          'lab_name': '测量实验',
          'course_name': '普通物理学实验',
          'teacher_name': '实验教师',
          'address': '东四 301',
          'dates': dates,
          'times': '10:00'
        }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Semester semester;
  setUp(() async {
    semester = Semester('2026-2027秋冬');
    semester.addZjuCalendar(
        jsonDecode((await BundledCalendarConfig.load('2026-2027-1'))!));
  });
  test('参考项目的名称地点日期时间转为课程时段', () {
    final lessons = parsePhysicsLabCourses(fixture());
    attachPhysicsLabCourses([semester], lessons);
    final course = semester.courses.values.single;
    expect(course.name, contains('普通物理学实验'));
    expect(course.sessions.single.name, '测量实验');
    expect(course.sessions.single.location, '东四 301');
    final period = semester.periods.single;
    expect(period.type, PeriodType.classes);
    expect(period.startTime, DateTime(2026, 10, 10, 10));
    expect(period.endTime, DateTime(2026, 10, 10, 12, 25));
    expect(period.fromUid, course.id);
    expect(course.sessions.single.chineseTime, contains('2026-10-10'));
  });
  test('多次实验有独立时段，重复同步和改期不会产生重复课', () {
    var lessons =
        parsePhysicsLabCourses(fixture(dates: '2026-10-10\n2026-10-17'));
    attachPhysicsLabCourses([semester], lessons);
    final uid = semester.periods.first.uid;
    attachPhysicsLabCourses([semester], lessons);
    expect(semester.courses, hasLength(1));
    expect(semester.periods, hasLength(2));
    lessons = parsePhysicsLabCourses(fixture(dates: '2026-10-11\n2026-10-18'));
    attachPhysicsLabCourses([semester], lessons);
    expect(semester.periods, hasLength(2));
    expect(semester.periods.first.uid, uid);
    expect(semester.periods.first.startTime, DateTime(2026, 10, 11, 10));
  });
  test('不会虚构每周重复，课程刷新后可以重新附加，附加数据不混入教务缓存', () {
    final lessons = parsePhysicsLabCourses(fixture());
    final base = semester.toJson();
    attachPhysicsLabCourses([semester], lessons);
    expect(semester.periods, hasLength(1));
    expect(semester.firstHalfTimetable.expand((e) => e), isNotEmpty);
    expect(semester.toJson()['sessions'], isEmpty);
    expect(semester.toJson()['courses'], isEmpty);
    final fresh = Semester.fromJson(base);
    attachPhysicsLabCourses([fresh], lessons);
    expect(fresh.periods, hasLength(1));
  });
  test('教务课程和学分保持，关闭导入移除实验附加层', () {
    final normal = Session.empty()
      ..id = '(2026-2027-1)-fixture'
      ..name = '原有课程'
      ..teacher = '教师'
      ..location = '教室'
      ..time = [1]
      ..firstHalf = true
      ..oddWeek = true
      ..evenWeek = true;
    semester.addSession(normal, '2026-2027-1');
    final original = semester.courses.values.single;
    original.credit = 2;
    final periods = semester.periods.length;
    attachPhysicsLabCourses([semester], parsePhysicsLabCourses(fixture()));
    expect(semester.courses, hasLength(2));
    expect(semester.periods.length, periods + 1);
    expect(semester.courseCredit, 2);
    attachPhysicsLabCourses([semester], []);
    expect(semester.courses.values.single, same(original));
    expect(semester.periods.length, periods);
  });
  test('服务器提供结束时间时优先使用，不套默认时长', () {
    final value = fixture();
    (value['rows'] as List).single['times'] = '10:00-12:00';
    attachPhysicsLabCourses([semester], parsePhysicsLabCourses(value));
    expect(semester.periods.single.endTime, DateTime(2026, 10, 10, 12));
  });
  test('教务部分刷新补全不会把实验来源复制到教务缓存', () {
    attachPhysicsLabCourses([semester], parsePhysicsLabCourses(fixture()));
    final incoming = Semester('2026-2027秋冬');
    incoming.mergePartialFrom(semester);
    expect(incoming.toJson()['courses'], isEmpty);
    expect(incoming.toJson()['sessions'], isEmpty);
  });
  test('损坏日期和缺少编号报错，账号之间的编号隔离', () {
    expect(() => parsePhysicsLabCourses(fixture(dates: '2026-02-30')),
        throwsFormatException);
    final bad = fixture();
    (bad['rows'] as List).single.remove('course_student_lab_id');
    expect(() => parsePhysicsLabCourses(bad), throwsFormatException);
    final left = parsePhysicsLabCourses(fixture());
    final right =
        parsePhysicsLabCourses({...fixture(), 'owner': 'another-account'});
    expect(left.single.uid, isNot(right.single.uid));
  });
  test('转换失败完整保留之前的附加课程', () {
    attachPhysicsLabCourses([semester], parsePhysicsLabCourses(fixture()));
    final previous = semester.periods.single;
    final value = fixture();
    (value['rows'] as List).single['times'] = '02:00';
    expect(
        () =>
            attachPhysicsLabCourses([semester], parsePhysicsLabCourses(value)),
        throwsFormatException);
    expect(semester.periods.single, same(previous));
    expect(semester.courses, hasLength(1));
  });
  test('一月实验按校历归属秋冬学期', () async {
    final calendar =
        jsonDecode((await BundledCalendarConfig.load('2026-2027-1'))!)
            as Map<String, dynamic>;
    final lessons = parsePhysicsLabCourses(fixture(dates: '2027-01-02'),
        calendars: {'2026-2027秋冬': calendar});
    expect(lessons.single.semesterName, '2026-2027秋冬');
    attachPhysicsLabCourses([semester], lessons);
    expect(semester.periods, hasLength(1));
    expect(semester.secondHalfTimetable.expand((e) => e), isNotEmpty);
  });
  test('关闭实验来源清理来源创建的空学期，保留教务学期', () async {
    final scholar = Scholar()..semesters = [Semester('2025-2026春夏')];
    final calendar =
        jsonDecode((await BundledCalendarConfig.load('2026-2027-1'))!)
            as Map<String, dynamic>;
    final owned = <String>{};
    var plan = planPhysicsLabCourses(scholar.semesters,
        parsePhysicsLabCourses(fixture()), {'2026-2027秋冬': calendar});
    installPhysicsLabCourses(scholar.semesters, plan, owned);
    expect(scholar.semesters, hasLength(2));
    expect(() => scholar.thisSemester, returnsNormally);
    plan = planPhysicsLabCourses(scholar.semesters, [], {});
    installPhysicsLabCourses(scholar.semesters, plan, owned);
    expect(scholar.semesters, hasLength(1));
    expect(() => scholar.thisSemester, returnsNormally);
  });
  test('选择实验来源仅替换确认课程的上课安排，保留成绩学分和其他课程，切回可恢复', () {
    Session regular(String name, String id) => Session.empty()
      ..id = id
      ..name = name
      ..teacher = '教师'
      ..location = '教室'
      ..time = [1]
      ..firstHalf = true
      ..oddWeek = true
      ..evenWeek = true;
    semester.addSession(regular('普通物理学实验', 'fixture-physics'), '2026-2027-1');
    semester.addSession(regular('其他课程', 'fixture-other'), '2026-2027-1');
    final academic = semester.courses.entries.first;
    academic.value.credit = 2;
    final base = semester.toJson();
    final lessons = parsePhysicsLabCourses(fixture());
    final plan = planPhysicsLabCourses([semester], lessons, {},
        replacements: {lessons.single.courseUid: academic.key});
    installPhysicsLabCourses([semester], plan, {});
    expect(semester.courses, hasLength(2));
    expect(semester.courses[academic.key]!.credit, 2);
    expect(semester.courses[academic.key]!.sessions.single.name, '测量实验');
    expect(semester.courses[academic.key]!.sessions.single.id, academic.key);
    expect(semester.sessions.where((s) => s.name == '普通物理学实验'), isEmpty);
    expect(semester.sessions.where((s) => s.name == '其他课程'), isNotEmpty);
    expect(semester.periods.where((p) => p.summary == '普通物理学实验'), isEmpty);
    expect(semester.periods.where((p) => p.summary == '其他课程'), isNotEmpty);
    expect(semester.physicsLabPeriods.single.fromUid, academic.key);
    expect(semester.toJson(), base);
    installPhysicsLabCourses(
        [semester], planPhysicsLabCourses([semester], [], {}), {});
    expect(semester.courses[academic.key], same(academic.value));
    expect(semester.sessions.where((s) => s.name == '普通物理学实验'), isNotEmpty);
  });
  test('重启反序列化且课程没有课号时，实验来源仍移除旧安排并保留考试和成绩', () {
    Session regular(String name) => Session.empty()
      ..name = name
      ..teacher = '教师'
      ..location = '教室'
      ..time = [1]
      ..firstHalf = true
      ..oddWeek = true
      ..evenWeek = true;
    semester.addSession(regular('普通物理学实验'), '2026-2027-1');
    semester.addSession(regular('其他课程'), '2026-2027-1');
    final key = semester.academicCourses.keys.first;
    final academic = semester.academicCourses[key]!;
    academic.grade = Grade({
      'xkkh': 'fixture-course',
      'kcmc': academic.name,
      'xf': 2,
      'cj': '优秀',
      'jd': 4.5
    });
    academic.credit = 2;
    final exam = Exam.empty()
      ..id = 'fixture-exam'
      ..name = academic.name
      ..time = [DateTime(2027, 1, 5, 10), DateTime(2027, 1, 5, 12)];
    academic.exams.add(exam);
    semester.exams.add(exam);
    final restored =
        Semester.fromJson(jsonDecode(jsonEncode(semester.toJson())));
    final lessons = parsePhysicsLabCourses(fixture());
    final plan = planPhysicsLabCourses([restored], lessons, {},
        replacements: {lessons.single.courseUid: key});
    installPhysicsLabCourses([restored], plan, {});
    expect(
        restored.firstHalfTimetable
            .expand((s) => s)
            .where((s) => s.name == '普通物理学实验'),
        isEmpty);
    expect(
        restored.periods.where(
            (p) => p.type == PeriodType.classes && p.summary == '普通物理学实验'),
        isEmpty);
    expect(restored.periods.where((p) => p.summary == '其他课程'), isNotEmpty);
    expect(
        restored.periods.where((p) => p.type == PeriodType.test), hasLength(1));
    expect(restored.courses[key]!.exams, hasLength(1));
    expect(restored.courses[key]!.grade!.original, '优秀');
    expect(restored.courseCredit, 2);
  });
}
