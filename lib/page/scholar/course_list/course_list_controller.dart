import 'package:celechron/page/scholar/semester_selection.dart';
import 'package:get/get.dart';

import 'package:celechron/model/semester.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/course.dart';

class CourseListController extends GetxController {
  final _scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  late final SemesterSelection _selection;
  RxInt get semesterIndex => _selection.index;

  CourseListController({required String initialName}) {
    _selection = SemesterSelection(_scholar, initialName);
  }

  Semester get semester => _selection.semester;
  List<Semester> get semesters => _scholar.value.semesters;

  List<Course> get courses => semester.courses.values.toList();
  @override
  void onClose() {
    _selection.dispose();
    super.onClose();
  }
}
