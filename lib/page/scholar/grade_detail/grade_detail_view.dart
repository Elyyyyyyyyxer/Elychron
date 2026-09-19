import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/app_route.dart';
import 'package:celechron/utils/tuple.dart';
import 'package:celechron/model/grade.dart';
import 'package:celechron/model/semester.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/two_line_card.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'grade_card.dart';
import 'grade_detail_controller.dart';
import 'package:celechron/utils/gpa_helper.dart';
import 'weighted_gpa_view.dart';

/// 取学期名里的"学年标记"（原来写死 `name.substring(2, 5)`，例如 `2026-2027秋冬` → `26-`）。
/// 名字短于 5 个字符时 substring 会抛 RangeError，这里退回原串。
String _semesterYearTag(String name) =>
    name.length >= 5 ? name.substring(2, 5) : name;

/// 学期卡片上的标题：原来是 `substring(2,5) + substring(7,11)`（`2026-2027秋冬` → `26-2027`）。
/// 名字不够长时同样会抛，这里退回原名， 观感不变，但不会再因为脏数据崩。
String _semesterChipTitle(String name) =>
    name.length >= 11 ? name.substring(2, 5) + name.substring(7, 11) : name;

class GradeDetailPage extends StatelessWidget {
  final _gradeDetailController = Get.put(GradeDetailController());

  GradeDetailPage({super.key}) {
    _gradeDetailController.init();
  }

  int getPairedSemesterIndex(int idx) {
    final list = _gradeDetailController.semestersWithGrades;
    if (idx < 0 || idx >= list.length) return idx;
    final tag = _semesterYearTag(list[idx].name);
    for (var i = 0; i < list.length; i++) {
      if (i != idx && _semesterYearTag(list[i].name) == tag) {
        return i;
      }
    }
    return idx;
  }

  Tuple<List<double>, double> getYearStats(int semesterIndex) {
    // ★ 没有成绩 / 下标越界时返回全 0，**绝不索引空列表**
    //   （2026-09-16：这一行是点成绩卡片就卡死的直接原因）
    final list = _gradeDetailController.semestersWithGrades;
    if (list.isEmpty || semesterIndex < 0 || semesterIndex >= list.length) {
      return Tuple([0.0, 0.0, 0.0], 0.0);
    }
    var s1 = list[semesterIndex];
    int another = getPairedSemesterIndex(semesterIndex);
    if (another == semesterIndex) {
      return Tuple([s1.gpa[0], s1.gpa[1], s1.gpa[2]], s1.credits);
    }
    var s2 = list[another];
    double credits = s1.credits + s2.credits;
    if (credits == 0) {
      return Tuple([0, 0, 0], 0);
    }
    return Tuple(
        List.generate(
            3,
            (int i) =>
                (s1.credits * s1.gpa[i] + s2.credits * s2.gpa[i]) / credits),
        credits);
  }

  Widget _buildGradeBrief(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Hero(
                tag: 'gradeBrief',
                child: RoundRectangleCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年学分',
                                content: getYearStats(
                                        _gradeDetailController.safeIndex)
                                    .item2
                                    .toStringAsFixed(1),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.sand)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年均绩',
                                content: getYearStats(
                                        _gradeDetailController.safeIndex)
                                    .item1[0]
                                    .toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.sakura)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年四分制',
                                content: getYearStats(
                                        _gradeDetailController.safeIndex)
                                    .item1[1]
                                    .toStringAsFixed(2),
                                extraContent: getYearStats(
                                        _gradeDetailController.safeIndex)
                                    .item1[2]
                                    .toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.magenta)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年主修学分',
                                content: _gradeDetailController
                                    .getYearMajorGpa(
                                        _gradeDetailController.safeIndex)
                                    .item2
                                    .toStringAsFixed(1),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.peach)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年主修均绩',
                                content: _gradeDetailController
                                    .getYearMajorGpa(
                                        _gradeDetailController.safeIndex)
                                    .item1[0]
                                    .toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.cyan)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '学年主修四分制',
                                content: _gradeDetailController
                                    .getYearMajorGpa(
                                        _gradeDetailController.safeIndex)
                                    .item1[1]
                                    .toStringAsFixed(2),
                                extraContent: _gradeDetailController
                                    .getYearMajorGpa(
                                        _gradeDetailController.safeIndex)
                                    .item1[2]
                                    .toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.spring)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCustomGpaBrief(BuildContext context) {
    List<Grade> inSelected = [], notSelected = [];
    for (var semester in _gradeDetailController.semestersWithGrades) {
      for (var grade in semester.grades) {
        if (_gradeDetailController.customGpaSelected[grade.id] ?? false) {
          inSelected.add(grade);
        } else {
          notSelected.add(grade);
        }
      }
    }
    var inGpa = GpaHelper.calculateGpa(inSelected);
    var notGpa = GpaHelper.calculateGpa(notSelected);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Hero(
                tag: 'gradeBrief',
                child: RoundRectangleCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '已选学分',
                                content: inGpa.item2.toStringAsFixed(1),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.sand)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '已选五分制',
                                content: inGpa.item1[0].toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.sakura)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '已选四分制',
                                content: inGpa.item1[1].toStringAsFixed(2),
                                extraContent: inGpa.item1[2].toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.magenta)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '已选百分制',
                                content: inGpa.item1[3].toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.peach)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '未选五分制',
                                content: notGpa.item1[0].toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.cyan)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Obx(() => TwoLineCard(
                                title: '未选四分制',
                                content: notGpa.item1[1].toStringAsFixed(2),
                                extraContent:
                                    notGpa.item1[2].toStringAsFixed(2),
                                backgroundColor:
                                    CustomCupertinoDynamicColors.spring)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  int getSelectedGradeCount(Semester semester) {
    int selectedCount = 0;
    for (var i in semester.grades) {
      if (_gradeDetailController.customGpaSelected[i.id] ?? false) {
        selectedCount++;
      }
    }
    return selectedCount;
  }

  Widget _buildHistory(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: RoundRectangleCard(
                animate: false,
                child: Column(
                  children: [
                    // Horizontal scrollable list to list all semesters
                    SizedBox(
                      height: 81,
                      child: Obx(
                        () => ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount:
                              _gradeDetailController.semestersWithGrades.length,
                          itemBuilder: (context, index) {
                            final semester = _gradeDetailController
                                .semestersWithGrades[index];

                            return Obx(
                              () => Row(
                                children: [
                                  Obx(
                                    () => TwoLineCard(
                                      animate: true,
                                      withColoredFont: true,
                                      width: 120,
                                      title: _semesterChipTitle(semester.name),
                                      content: _gradeDetailController
                                              .customGpaMode.value
                                          ? '${getSelectedGradeCount(semester)} / ${semester.grades.length}'
                                          : '${semester.gpa[0].toStringAsFixed(2)}/${semester.credits.toStringAsFixed(1)}',
                                      onTap: () {
                                        _gradeDetailController
                                            .semesterIndex.value = index;
                                        _gradeDetailController.semesterIndex
                                            .refresh();
                                      },
                                      onLongPress: _gradeDetailController
                                              .customGpaMode.value
                                          ? () {
                                              _gradeDetailController
                                                  .semesterIndex.value = index;
                                              _gradeDetailController
                                                  .semesterIndex
                                                  .refresh();
                                              _gradeDetailController
                                                  .toggleSemesterSelection(
                                                      index);
                                            }
                                          : null,
                                      backgroundColor: _gradeDetailController
                                                  .semesterIndex.value ==
                                              index
                                          ? CustomCupertinoDynamicColors.cyan
                                          : CupertinoColors.systemFill,
                                    ),
                                  ),
                                  if (index !=
                                      _gradeDetailController
                                              .semestersWithGrades.length -
                                          1)
                                    const SizedBox(width: 6),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  /// 一门成绩都没有时的页面， 这是**正常的空状态，不是错误**。
  ///
  /// 为什么要单独一个页面：见 [build] 开头的注释（原来的写法会直接抛 RangeError）。
  Widget _buildNoGrades(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(
        slivers: [
          const CelechronSliverTextHeader(subtitle: '成绩'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: RoundRectangleCard(
                animate: false,
                child: Column(
                  children: [
                    Icon(CupertinoIcons.chart_bar_alt_fill,
                        size: 32, color: labelColor),
                    const SizedBox(height: 10),
                    Text('还没有成绩',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: labelColor)),
                    const SizedBox(height: 6),
                    Text(
                      '等教务把成绩放出来，这里会自动显示。也可以在学业页下拉刷新一次试试。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: labelColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ===== MOD ===== 末尾垫出系统导航栏的高度（否则底部内容会被压掉）
          SliverToBoxAdapter(
            child: SizedBox(
              height: 16 + MediaQuery.of(context).padding.bottom,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ===== MOD: 一门成绩都没有时，**绝不能**去索引 semestersWithGrades =====
    //
    // 2026-09-16 用户报点击成绩卡片任意位置会卡死，真机复现：
    //   成绩页构建时 `semestersWithGrades[semesterIndex.value]` 在**空列表**上取下标
    //   → `RangeError (length): Invalid value: Valid value range is empty: 0`
    //   而这里在 `Obx` 的 builder 里 → GetX 的 `RxInterface.proxy` 被永久留在这个
    //   构建失败的 Obx 上（get 4.7.3 `notifyChildren` 抛错时不恢复代理）
    //   → 全 App 的 Rx 读取都挂到这个死观察者上、反复触发它重建、每次都再抛一次
    //   → **主线程 100% CPU 空转**，5 秒后系统弹Elychron 无响应（ANR）。
    //   真机 ANR 报告佐证：主线程 state=R、utm=23.5s，一直在 libapp.so（Dart AOT）里跑。
    //
    // 所以先挡住"没有成绩"这个**正常状态**：显示一句人话，一个下标都不碰。
    if (!_gradeDetailController.hasGrades) {
      return _buildNoGrades(context);
    }
    return CupertinoPageScaffold(
      backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground, context),
      child: CustomScrollView(
        slivers: [
          CelechronSliverTextHeader(
            subtitle: '成绩',
            right: Obx(
              () => Padding(
                padding: const EdgeInsets.only(right: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_gradeDetailController.customGpaMode.value)
                      GestureDetector(
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          child: const Text('长按清空'),
                          onPressed: () {},
                        ),
                        onLongPress: () {
                          _gradeDetailController.customGpaSelected.value = {};
                          _gradeDetailController.refreshCustomGpa();
                        },
                      ),
                    if (_gradeDetailController.customGpaMode.value)
                      const SizedBox(width: 8),
                    // 加权绩点入口按钮（仅在非自定义GPA模式下显示）
                    // 点击后跳转到加权绩点页面，可设置各课程的加权比例（0.8-1.2）
                    if (!_gradeDetailController.customGpaMode.value)
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Icon(
                          CupertinoIcons.chart_bar_alt_fill,
                          semanticLabel: 'Weighted GPA',
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            appPageRoute(
                              builder: (context) => WeightedGpaPage(),
                            ),
                          );
                        },
                      ),
                    // if (!_gradeDetailController.customGpaMode.value)
                    //   const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Icon(
                        _gradeDetailController.customGpaMode.value
                            ? CupertinoIcons
                                .square_fill_line_vertical_square_fill
                            : CupertinoIcons.square_line_vertical_square,
                        semanticLabel: 'Custom GPA',
                      ),
                      onPressed: () {
                        _gradeDetailController.customGpaMode.value =
                            !_gradeDetailController.customGpaMode.value;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        children: [
                          Obx(() => _gradeDetailController.customGpaMode.value
                              ? _buildCustomGpaBrief(context)
                              : _buildGradeBrief(context)),
                          _buildHistory(context),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                )
              ],
            ),
          ),
          Obx(
            () => SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 18),
                          Expanded(
                            child: GradeCard(
                              grade: _gradeDetailController
                                  .semestersWithGrades[
                                      _gradeDetailController.safeIndex]
                                  .grades[index],
                            ),
                          ),
                          const SizedBox(width: 18),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
                childCount: _gradeDetailController
                    .semestersWithGrades[_gradeDetailController.safeIndex]
                    .grades
                    .length,
              ),
            ),
          ),
          // ===== MOD ===== 末尾垫出系统导航栏的高度（否则最后一张卡会被压掉一半）
          SliverToBoxAdapter(
            child: SizedBox(
              height: 16 + MediaQuery.of(context).padding.bottom,
            ),
          ),
        ],
      ),
    );
  }
}
