import 'dart:convert';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/calendar_bundled_config.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/model/session.dart';
import 'package:celechron/mod/physics_lab_courses.dart';
import 'package:celechron/mod/physics_lab_page.dart';
import 'package:celechron/mod/physics_lab_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

class MemoryOptions implements Box<dynamic> {
  final _data = <dynamic, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _data[key] = value;
  }

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    _data.addAll(entries);
  }

  @override
  Future<void> delete(dynamic key) async {
    _data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    for (final id in BundledCalendarConfig.bundledSemesters) {
      await BundledCalendarConfig.load(id);
    }
  });
  testWidgets('用户选择教务或实验来源，并明确对应课程后才替换上课安排', (tester) async {
    final db = DatabaseHelper()..optionsBox = MemoryOptions();
    Get.put(db, tag: 'db');
    final semester = Semester('2026-2027秋冬');
    semester.addZjuCalendar(
        jsonDecode((await BundledCalendarConfig.load('2026-2027-1'))!));
    semester.addSession(
        Session.empty()
          ..name = '普通物理学实验'
          ..teacher = '教师'
          ..location = '教室'
          ..time = [1]
          ..firstHalf = true
          ..oddWeek = true
          ..evenWeek = true,
        '2026-2027-1');
    final scholar = (Scholar()..semesters = [semester]).obs;
    Get.put(scholar, tag: 'scholar');
    final lesson = PhysicsLabLesson(
        uid: 'fixture-lab',
        courseUid: 'fixture-course',
        course: '普物实验',
        title: '测试实验',
        teacher: '教师',
        location: '教室',
        start: DateTime(2026, 10, 10, 10),
        end: DateTime(2026, 10, 10, 12));
    await db.optionsBox.putAll({
      'physicsLabEnabled': true,
      'physicsLabCourseCache': jsonEncode({
        'ownerScope': 'fixture-scope',
        'linkedScholarScope': '',
        'createdSemesters': [],
        'lessons': [lesson.toJson()]
      }),
    });
    await tester.pumpWidget(const CupertinoApp(home: PhysicsLabPage()));
    await tester.pumpAndSettle();
    expect(find.text('未选择，保留教务课表'), findsOneWidget);
    await tester.tap(find.text('最终课表来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用教务课表'));
    await tester.pumpAndSettle();
    expect(semester.physicsLabPeriods, isEmpty);
    await tester.tap(find.text('最终课表来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用实验选课系统'));
    await tester.pumpAndSettle();
    expect(find.text('选择这门实验对应的教务课程，仅替换它的上课安排。'), findsOneWidget);
    expect(semester.physicsLabPeriods, isEmpty);
    await tester.tap(find.text('普通物理学实验'));
    await tester.pumpAndSettle();
    expect(semester.physicsLabPeriods, hasLength(1));
    expect(semester.periods.where((p) => p.summary == '普通物理学实验'), isEmpty);
    await tester.tap(find.text('最终课表来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用教务课表'));
    await tester.pumpAndSettle();
    expect(semester.physicsLabPeriods, isEmpty);
    expect(semester.periods.where((p) => p.summary == '普通物理学实验'), isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    PhysicsLabService.instance.dispose();
    Get.reset();
  });
}
