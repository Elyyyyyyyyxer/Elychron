import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';
import 'package:get/get.dart';

/// 学期来源可以插入、删除和重排；选择用名称保持身份，索引只供现有菜单使用。
class SemesterSelection {
  final Rx<Scholar> scholar;
  final RxInt index = 0.obs;
  late String _name;
  late final Worker _scholarObserver;
  late final Worker _indexObserver;

  SemesterSelection(this.scholar, String initialName) {
    _name = initialName;
    _reconcile();
    _indexObserver = ever<int>(index, (value) {
      final semesters = scholar.value.semesters;
      if (value >= 0 && value < semesters.length) _name = semesters[value].name;
    });
    _scholarObserver = ever<Scholar>(scholar, (_) => _reconcile());
  }

  void _reconcile() {
    final semesters = scholar.value.semesters;
    final found = semesters.indexWhere((s) => s.name == _name);
    index.value = found < 0 ? 0 : found;
    if (found < 0 && semesters.isNotEmpty) _name = semesters.first.name;
  }

  Semester get semester {
    final semesters = scholar.value.semesters;
    // Get observers can rebuild before the selection observer has run.
    return semesters.firstWhereOrNull((s) => s.name == _name) ??
        (semesters.isEmpty ? Semester('未刷新') : semesters.first);
  }

  void dispose() {
    _scholarObserver.dispose();
    _indexObserver.dispose();
  }
}
