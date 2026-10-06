import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:celechron/model/course.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/model/session.dart';

class PhysicsLabLesson {
  final String uid;
  final String courseUid;
  final String course;
  final String title;
  final String teacher;
  final String location;
  final DateTime start;
  final DateTime end;
  final String? calendarSemester;
  const PhysicsLabLesson(
      {required this.uid,
      required this.courseUid,
      required this.course,
      required this.title,
      required this.teacher,
      required this.location,
      required this.start,
      required this.end,
      this.calendarSemester});

  String get semesterName {
    if (calendarSemester != null) return calendarSemester!;
    final autumn = start.month >= 8 || start.month <= 1;
    final year = start.month >= 8 ? start.year : start.year - 1;
    return '$year-${year + 1}${autumn ? '秋冬' : '春夏'}';
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'courseUid': courseUid,
        'course': course,
        'title': title,
        'teacher': teacher,
        'location': location,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'semester': calendarSemester
      };

  factory PhysicsLabLesson.fromJson(Map<String, dynamic> value) {
    final start = DateTime.parse(value['start'] as String);
    final end = DateTime.parse(value['end'] as String);
    if (!end.isAfter(start)) throw const FormatException('实验结束时间无效');
    return PhysicsLabLesson(
        uid: value['uid'] as String,
        courseUid: value['courseUid'] as String,
        course: value['course'] as String,
        title: value['title'] as String,
        teacher: value['teacher'] as String,
        location: value['location'] as String,
        start: start,
        end: end,
        calendarSemester: value['semester'] as String?);
  }
}

/// 字段映射参考 5dbwat4/zjuphylab.ics；无结束时间时沿用其 2 小时 25 分钟。
List<PhysicsLabLesson> parsePhysicsLabCourses(Map<String, dynamic> value,
    {Map<String, Map<String, dynamic>> calendars = const {}}) {
  final owner = value['owner']?.toString() ?? '';
  final rows = value['rows'];
  if (owner.isEmpty || rows is! List) throw const FormatException('课表结构已变化');
  final scope = sha256.convert(utf8.encode(owner)).toString().substring(0, 16);
  final lessons = <String, PhysicsLabLesson>{};
  for (final raw in rows) {
    if (raw is! Map) throw const FormatException('实验条目无效');
    String text(String key) => raw[key]?.toString().trim() ?? '';
    final term = text('term_id');
    final courseId = text('course_id');
    final selection = text('course_student_lab_id');
    final title = text('lab_name');
    if ([term, courseId, selection, title].any((s) => s.isEmpty)) {
      throw const FormatException('实验条目缺少名称或稳定编号');
    }
    final times = RegExp(r'^(\d{1,2}:\d{2})(?:\s*[-~—至]\s*(\d{1,2}:\d{2}))?$')
        .firstMatch(text('times'));
    final dates = text('dates')
        .split(RegExp(r'[\s,;，；]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (times == null || dates.isEmpty) {
      throw const FormatException('实验日期或钟点无效');
    }
    for (var index = 0; index < dates.length; index++) {
      final start = _at(dates[index], times.group(1)!);
      final end = times.group(2) == null
          ? start.add(const Duration(minutes: 145))
          : _at(dates[index], times.group(2)!);
      if (!end.isAfter(start)) throw const FormatException('实验结束时间无效');
      final uid = 'phylab-$scope-$term-$courseId-$selection-$index';
      lessons[uid] = PhysicsLabLesson(
          uid: uid,
          courseUid: 'phylab-$scope-$term-$courseId',
          course: text('course_name'),
          title: title,
          teacher: text('teacher_name'),
          location: text('address'),
          start: start,
          end: end,
          calendarSemester: _calendarSemester(start, calendars));
    }
  }
  return lessons.values.toList()..sort((a, b) => a.start.compareTo(b.start));
}

DateTime _at(String date, String clock) {
  final d = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (d == null) throw const FormatException('实验日期无效');
  final year = int.parse(d.group(1)!);
  final month = int.parse(d.group(2)!);
  final day = int.parse(d.group(3)!);
  final parts = clock.split(':').map(int.parse).toList();
  final result = DateTime(year, month, day, parts[0], parts[1]);
  if (result.year != year ||
      result.month != month ||
      result.day != day ||
      parts[0] > 23 ||
      parts[1] > 59) {
    throw const FormatException('实验日期或钟点无效');
  }
  return result;
}

void _fillPhysicsLabCourses(
    List<Semester> semesters, List<PhysicsLabLesson> lessons) {
  for (final semester in semesters) {
    semester.physicsLabCourses = {};
    semester.physicsLabSessions = [];
    semester.physicsLabPeriods = [];
    final calendar = semester.toJson()['dayOfWeekToDays'] as List;
    final firstDates = <DateTime>[];
    if (calendar.isNotEmpty) {
      for (final oddEven in calendar.first as List) {
        for (final days in oddEven as List) {
          firstDates
              .addAll((days as List).map((s) => DateTime.parse(s as String)));
        }
      }
    }
    firstDates.sort();
    final firstEnd = firstDates.isEmpty
        ? null
        : firstDates.last.add(const Duration(days: 1));
    final sessions = <String, _PhysicsLabSession>{};
    for (final lesson
        in lessons.where((l) => semester.name.startsWith(l.semesterName))) {
      final key =
          '${lesson.courseUid}|${lesson.title}|${lesson.location}|${lesson.start.weekday}|${_clock(lesson.start)}|${_clock(lesson.end)}';
      final session = sessions.putIfAbsent(
          key, () => _PhysicsLabSession(lesson, _slots(semester, lesson)));
      session.dates.add(lesson.start);
      if (firstEnd == null || lesson.start.isBefore(firstEnd)) {
        session.firstHalf = true;
      } else {
        session.secondHalf = true;
      }
      final course = semester.physicsLabCourses.putIfAbsent(
          lesson.courseUid,
          () => Course.fromUgrsSessionWithoutID(session)
            ..id = lesson.courseUid
            ..name =
                '${lesson.course.isEmpty ? '普通物理实验' : lesson.course}（实验选课）');
      if (!course.sessions.contains(session)) course.sessions.add(session);
      semester.physicsLabPeriods.add(Period(
          uid: lesson.uid,
          fromUid: lesson.courseUid,
          summary: lesson.title,
          description: '普物实验选课系统\n教师：${lesson.teacher}',
          location: lesson.location,
          startTime: lesson.start,
          endTime: lesson.end));
    }
    semester.physicsLabSessions = sessions.values.toList();
  }
}

List<int> _slots(Semester semester, PhysicsLabLesson lesson) {
  final start = lesson.start.hour * 60 + lesson.start.minute;
  final end = lesson.end.hour * 60 + lesson.end.minute;
  final slots = <int>[];
  for (var i = 1; i <= 15; i++) {
    final range = semester.clockRangeOf(i, i);
    if (range == null) continue;
    final clocks = RegExp(r'(\d{2}):(\d{2})').allMatches(range).toList();
    if (clocks.length != 2) continue;
    int minute(RegExpMatch m) =>
        int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
    if (minute(clocks.first) < end && minute(clocks.last) > start) slots.add(i);
  }
  if (slots.isEmpty) throw const FormatException('当前校历无法定位实验节次');
  return slots;
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

class _PhysicsLabSession extends Session {
  final PhysicsLabLesson lesson;
  final List<DateTime> dates = [];
  _PhysicsLabSession(this.lesson, List<int> slots) : super.empty() {
    id = lesson.courseUid;
    name = lesson.title;
    teacher = lesson.teacher;
    location = lesson.location;
    time = slots;
    dayOfWeek = lesson.start.weekday;
    oddWeek = true;
    evenWeek = true;
  }
  @override
  String get explicitClockRange =>
      '${_clock(lesson.start)} - ${_clock(lesson.end)}';
  @override
  String get chineseTime =>
      dates.map((d) => d.toIso8601String().substring(0, 10)).join('、');
}

// Build every projection before changing the live timetable.
void attachPhysicsLabCourses(
    List<Semester> semesters, List<PhysicsLabLesson> lessons) {
  final plan = planPhysicsLabCourses(semesters, lessons, {});
  for (var i = 0; i < semesters.length; i++) {
    semesters[i].applyPhysicsLabProjection(plan[i]);
  }
}

List<Semester> planPhysicsLabCourses(
    List<Semester> semesters,
    List<PhysicsLabLesson> lessons,
    Map<String, Map<String, dynamic>> calendars) {
  final plan = semesters
      .map((s) => Semester.fromJson({
            ...s.toJson(),
            'courses': {},
            'sessions': [],
            'exams': [],
            'grades': [],
          }))
      .toList();
  for (final name in lessons.map((l) => l.semesterName).toSet()) {
    final matches = plan.where((s) => s.name.startsWith(name));
    final semester = matches.isEmpty ? Semester(name) : matches.first;
    if (!semester.hasCalendar) {
      final calendar = calendars[name];
      if (calendar == null) throw const FormatException('缺少对应学期校历');
      semester.addZjuCalendar(calendar);
    }
    if (matches.isEmpty) plan.add(semester);
  }
  _fillPhysicsLabCourses(plan, lessons);
  return plan;
}

void installPhysicsLabCourses(List<Semester> semesters, List<Semester> plan,
    Set<String> createdSemesterNames) {
  for (final projection in plan) {
    final matches = semesters.where((s) => s.name == projection.name);
    if (matches.isEmpty) {
      semesters.add(projection);
      createdSemesterNames.add(projection.name);
    } else {
      matches.first.applyPhysicsLabProjection(projection);
    }
  }
  semesters.removeWhere((s) {
    if (!createdSemesterNames.contains(s.name) ||
        s.physicsLabPeriods.isNotEmpty) {
      return false;
    }
    final json = s.toJson();
    if ((json['courses'] as Map).isNotEmpty ||
        ['sessions', 'exams', 'grades']
            .any((key) => (json[key] as List).isNotEmpty)) {
      return false;
    }
    createdSemesterNames.remove(s.name);
    return true;
  });
  // Match Scholar's existing order (newest semester first).
  semesters.sort((a, b) => b.name.compareTo(a.name));
}

String? _calendarSemester(
    DateTime date, Map<String, Map<String, dynamic>> calendars) {
  for (final entry in calendars.entries) {
    final bounds = entry.value['startEnd'];
    if (bounds is! List || bounds.length != 4) continue;
    DateTime parse(Object? value) {
      final text = value.toString();
      return DateTime.parse(text.length == 8
          ? '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}'
          : text);
    }

    final first = parse(bounds.first);
    final afterLast = parse(bounds.last).add(const Duration(days: 1));
    if (!date.isBefore(first) && date.isBefore(afterLast)) return entry.key;
  }
  return null;
}
