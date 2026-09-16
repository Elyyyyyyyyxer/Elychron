import 'package:celechron/database/database_helper.dart';
import 'package:get/get.dart';

import 'package:celechron/model/semester.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/utils/tuple.dart';
import 'package:celechron/utils/gpa_helper.dart';

class GradeDetailController extends GetxController {
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final semesterIndex = 0.obs;
  final customGpaMode = false.obs;
  final _db = Get.find<DatabaseHelper>(tag: 'db');
  final RxMap<String, bool> customGpaSelected = RxMap();
  late RxList<Semester> semestersWithGrades;

  void init() {
    semestersWithGrades = scholar.value.semesters
        .where((element) => element.grades.isNotEmpty)
        .toList()
        .obs;
    ever(scholar, (callback) => refreshSemesters());
    customGpaSelected.value = _db.getCustomGpa();
    semesterIndex.value = 0;
    customGpaMode.value = false;
  }

  @override
  void onInit() {
    init();
    super.onInit();
  }

  /// 当前选中的学期下标，**保证落在合法范围内**。
  ///
  /// ★ 为什么必须有它（2026-09-16 的真机事故）：
  /// `semestersWithGrades` 会随刷新变化 —— 成绩还没出、被清空、或者某个学期被过滤掉时
  /// 它的长度会是 **0**，而 `semesterIndex` 是独立存的一个数字。
  /// 页面里原来到处直接写 `semestersWithGrades[semesterIndex.value]`，
  /// 于是**一门成绩都没有的人点开成绩页 → RangeError → App 卡死（系统 ANR）**。
  /// 所有取值都走这里，就再也不会越界。
  int get safeIndex {
    final list = semestersWithGrades;
    if (list.isEmpty) return 0;
    final index = semesterIndex.value;
    return (index >= 0 && index < list.length) ? index : 0;
  }

  /// 有没有任何学期的成绩（没有的话页面直接显示"还没有成绩"，不去碰下标）
  bool get hasGrades => semestersWithGrades.isNotEmpty;

  void refreshSemesters() {
    semestersWithGrades.value = scholar.value.semesters
        .where((element) => element.grades.isNotEmpty)
        .toList();
    semestersWithGrades.refresh();
    // 列表可能变短了（甚至变空）→ 把下标收回合法范围
    if (semestersWithGrades.isNotEmpty &&
        semesterIndex.value >= semestersWithGrades.length) {
      semesterIndex.value = 0;
    }
  }

  void refreshCustomGpa() {
    _db.setCustomGpa(customGpaSelected);
  }

  Tuple<List<double>, double> getYearMajorGpa(int semesterIndex) {
    // ★ 先挡住"没有成绩 / 下标越界"：这里原来直接取 [semesterIndex]，列表一空就抛
    final list = semestersWithGrades;
    if (list.isEmpty || semesterIndex < 0 || semesterIndex >= list.length) {
      return Tuple([0.0, 0.0, 0.0], 0.0);
    }

    // 提取当前学期的学年 ID，例如 "2022-2023"
    // （名字短于 9 个字符时 substring 也会抛，所以先判长度）
    final name = list[semesterIndex].name;
    final yearId = name.length >= 9 ? name.substring(0, 9) : name;

    // 获取该学年的所有主修课程
    final majorGrades = scholar.value.grades.values
        .expand((g) => g)
        .where((g) => g.major && g.semesterId.contains(yearId))
        .toList();

    // 如果该学年没有主修课程，返回 0.0, 0.0, 0.0
    if (majorGrades.isEmpty) {
      return Tuple([0.0, 0.0, 0.0], 0.0);
    }

    return GpaHelper.calculateGpa(majorGrades);
  }

  /// 检查指定学期的所有课程是否已全选
  bool isSemesterAllSelected(int semesterIndex) {
    if (semesterIndex < 0 || semesterIndex >= semestersWithGrades.length) {
      return false;
    }
    final semester = semestersWithGrades[semesterIndex];
    if (semester.grades.isEmpty) {
      return false;
    }
    for (var grade in semester.grades) {
      if (customGpaSelected[grade.id] != true) {
        return false;
      }
    }
    return true;
  }

  /// 全选指定学期的所有课程
  void selectAllGradesInSemester(int semesterIndex) {
    if (semesterIndex < 0 || semesterIndex >= semestersWithGrades.length) {
      return;
    }
    final semester = semestersWithGrades[semesterIndex];
    for (var grade in semester.grades) {
      customGpaSelected[grade.id] = true;
    }
    refreshCustomGpa();
  }

  /// 清空指定学期的所有课程选择
  void clearGradesInSemester(int semesterIndex) {
    if (semesterIndex < 0 || semesterIndex >= semestersWithGrades.length) {
      return;
    }
    final semester = semestersWithGrades[semesterIndex];
    for (var grade in semester.grades) {
      customGpaSelected[grade.id] = false;
    }
    refreshCustomGpa();
  }

  /// 切换指定学期的选择状态：如果已全选则清空，否则全选
  void toggleSemesterSelection(int semesterIndex) {
    if (isSemesterAllSelected(semesterIndex)) {
      clearGradesInSemester(semesterIndex);
    } else {
      selectAllGradesInSemester(semesterIndex);
    }
  }
}
