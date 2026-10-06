import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/mod/physics_lab_courses.dart';
import 'package:celechron/mod/physics_lab_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

class DelayedOptions implements Box<dynamic> {
  final Box<dynamic> base;
  final started = Completer<void>();
  final allow = Completer<void>();
  DelayedOptions(this.base);
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      base.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (!started.isCompleted) {
      started.complete();
      await allow.future;
    }
    await base.put(key, value);
  }

  @override
  Future<void> delete(dynamic key) => base.delete(key);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
      'physicsLabTimetableChoice': jsonEncode({
        'ownerScope': 'fixture-scope',
        'source': 'physics',
        'courses': {'fixture-course': ''}
      }),
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
  test('首次同步未选择来源时不叠加课表，明确选择后只显示所选来源', () async {
    final db = Get.find<DatabaseHelper>(tag: 'db');
    await db.optionsBox.delete('physicsLabTimetableChoice');
    await service.start();
    expect(service.timetableSource, isNull);
    expect(derivedCalendar, isEmpty);
    await service.setTimetableSource('academic');
    expect(service.timetableSource, 'academic');
    expect(derivedCalendar, isEmpty);
    await service.setTimetableSource('physics');
    expect(derivedCalendar, isEmpty, reason: '未确认对应课程前不能叠加');
    await service.setCourseReplacement('fixture-course', '');
    expect(derivedCalendar, ['fixture-lab']);
    await service.setTimetableSource('academic');
    expect(derivedCalendar, isEmpty);
    final stored = jsonDecode(
        db.optionsBox.get('physicsLabTimetableChoice:fixture-scope'));
    expect(stored['source'], 'academic');
  });

  test('保存来源时切换账号，不把旧选择提交到当前账号，返回原账号保持原来源', () async {
    await service.start();
    final db = Get.find<DatabaseHelper>(tag: 'db');
    final delayed = DelayedOptions(db.optionsBox);
    Get.delete<DatabaseHelper>(tag: 'db');
    Get.put(DatabaseHelper()..optionsBox = delayed, tag: 'db');
    final saving = service.setTimetableSource('academic');
    await delayed.started.future;
    scholar.value.username = 'different-fixture-account';
    scholar.refresh();
    delayed.allow.complete();
    await saving;
    scholar.value.username = '';
    scholar.refresh();
    expect(service.timetableSource, 'physics');
    expect(derivedCalendar, ['fixture-lab']);
  });

  test('来源选择重启后仍保留，切回教务清理来源创建的空学期', () async {
    final db = Get.find<DatabaseHelper>(tag: 'db');
    await db.optionsBox.delete('physicsLabTimetableChoice');
    await service.start();
    await service.setTimetableSource('physics');
    await service.setCourseReplacement('fixture-course', '');
    final stored = jsonDecode(
            jsonEncode(scholar.value.semesters.map((s) => s.toJson()).toList()))
        as List;
    service.dispose();
    scholar.value.semesters = stored
        .map((s) => Semester.fromJson(Map<String, dynamic>.from(s)))
        .toList();
    service = PhysicsLabService.forTesting();
    await service.start();
    expect(service.timetableSource, 'physics');
    expect(derivedCalendar, ['fixture-lab']);
    await service.setTimetableSource('academic');
    expect(derivedCalendar, isEmpty);
    expect(scholar.value.semesters, isEmpty);
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
