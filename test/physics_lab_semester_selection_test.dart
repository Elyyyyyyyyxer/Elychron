import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/page/scholar/course_schedule/course_schedule_controller.dart';
import 'package:celechron/page/scholar/course_list/course_list_controller.dart';
import 'package:celechron/page/scholar/exam_list/exam_list_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  for (final create in <String, dynamic Function(String)>{
    '课表': (name) => CourseScheduleController(
        initialName: name, initialFirstOrSecondSemester: true),
    '课程列表': (name) => CourseListController(initialName: name),
    '考试列表': (name) => ExamListController(initialName: name),
  }.entries) {
    test('${create.key}在实验学期增删排序后保持选择，学期消失安全回退', () {
      final original = Semester('2025-2026春夏');
      final lab = Semester('2026-2027秋冬');
      final scholar = (Scholar()..semesters = [original]).obs;
      Get.put(scholar, tag: 'scholar');
      final controller = create.value(original.name);
      scholar.value.semesters.insert(0, lab);
      scholar.refresh();
      expect(controller.semester, same(original));
      expect(controller.semesterIndex.value, 1);
      scholar.value.semesters.remove(lab);
      scholar.refresh();
      expect(controller.semester, same(original));
      expect(controller.semesterIndex.value, 0);
      scholar.value.semesters = [];
      scholar.refresh();
      expect(() => controller.semester, returnsNormally);
      if (controller is CourseScheduleController) {
        expect(() => controller.sessionsByDayOfWeek, returnsNormally);
      }
      controller.onClose();
      Get.reset();
    });
  }
}
