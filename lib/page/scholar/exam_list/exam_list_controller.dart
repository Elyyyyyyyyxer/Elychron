import 'package:celechron/page/scholar/semester_selection.dart';
import 'dart:async';

import 'package:get/get.dart';

import 'package:celechron/model/semester.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/exam.dart';

class ExamListController extends GetxController {
  final _scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  late final SemesterSelection _selection;
  RxInt get semesterIndex => _selection.index;
  final Rx<Duration> _durationToLastUpdate = const Duration().obs;
  Timer? _timer;

  ExamListController({required String initialName}) {
    _selection = SemesterSelection(_scholar, initialName);
  }

  Semester get semester => _selection.semester;
  List<Semester> get semesters => _scholar.value.semesters;
  Duration get durationToLastUpdate => _durationToLastUpdate.value;

  List<List<Exam>> get exams {
    semester.sortExams();
    final groupedExams = <String, List<Exam>>{};
    for (final exam in semester.exams) {
      groupedExams.putIfAbsent(_examDayKey(exam), () => []).add(exam);
    }
    return groupedExams.values.toList();
  }

  String _examDayKey(Exam exam) {
    if (exam.dateLabel != null) return 'label:${exam.dateLabel}';
    final date = exam.time[0];
    return 'date:${date.year}-${date.month}-${date.day}';
  }

  @override
  void onReady() {
    super.onReady();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _durationToLastUpdate.value =
          DateTime.now().difference(_scholar.value.lastUpdateTimeCourse);
    });
  }

  @override
  void onClose() {
    _selection.dispose();
    _timer?.cancel();
    super.onClose();
  }
}
