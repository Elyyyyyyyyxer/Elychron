import 'package:celechron/page/scholar/semester_selection.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/model/session.dart';
import 'package:get/get.dart';
import 'package:celechron/model/scholar.dart';

class CourseScheduleController extends GetxController {
  final _scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  late final SemesterSelection _selection;
  RxInt get semesterIndex => _selection.index;
  late final RxBool firstOrSecondSemester;

  Semester get semester => _selection.semester;
  List<Semester> get semesters => _scholar.value.semesters;

  void init(String initialName, bool initialFirstOrSecondSemester) {
    _selection = SemesterSelection(_scholar, initialName);
    firstOrSecondSemester = initialFirstOrSecondSemester.obs;
  }

  CourseScheduleController({
    required String initialName,
    required bool initialFirstOrSecondSemester,
  }) {
    init(initialName, initialFirstOrSecondSemester);
  }

  List<List<Session>> get sessionsByDayOfWeek => firstOrSecondSemester.value
      ? semester.firstHalfTimetable
      : semester.secondHalfTimetable;
  @override
  void onClose() {
    _selection.dispose();
    super.onClose();
  }
}
