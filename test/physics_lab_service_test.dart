import 'dart:convert';
import 'dart:io';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/mod/physics_lab_courses.dart';
import 'package:celechron/mod/physics_lab_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PhysicsLabService service;
  late Rx<Scholar> scholar;
  late Worker observer;
  late List<String> derivedCalendar;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('physics-lab-test-');
    Hive.init(directory.path);
    final db = DatabaseHelper()..optionsBox = await Hive.openBox('options');
    Get.put(db, tag: 'db');
    scholar = Scholar().obs;
    Get.put(scholar, tag: 'scholar');
    // Calendar/Flow observers are registered before the delayed source restoration.
    derivedCalendar = [];
    observer = ever<Scholar>(scholar, (s) {
      derivedCalendar = s.periods.map((p) => p.uid).toList();
    });
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
        'createdSemesters': <String>[],
        'lessons': [lesson.toJson()],
      }),
    });
    service = PhysicsLabService.forTesting();
  });
  tearDown(() async {
    observer.dispose();
    service.dispose();
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test('离线启动恢复实验后通知已初始化的日历，无需网络刷新', () async {
    await service.start();
    expect(derivedCalendar, ['fixture-lab']);
  });
  test('教务整批替换学期后重新附加并通知先注册的日历观察者', () async {
    await service.start();
    scholar.value.semesters = [Semester('2026-2027秋冬')];
    scholar.refresh();
    expect(derivedCalendar, ['fixture-lab']);
  });
  test('切换教务账号隐藏旧实验，关闭同步不会留下空来源学期', () async {
    await service.start();
    scholar.value.username = 'different-fixture-account';
    scholar.refresh();
    expect(derivedCalendar, isEmpty);
    expect(service.lessons, isEmpty);
    expect(scholar.value.semesters, isEmpty);
  });
}
