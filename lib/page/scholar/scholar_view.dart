// Official packages
import 'package:celechron/page/scholar/todo/todo_card.dart';
import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// Custom widgets and colors
import 'package:celechron/design/multiple_columns.dart';
import 'package:celechron/design/two_line_card.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/animate_button.dart';
import 'package:celechron/design/refresh_status_indicator.dart';
import 'package:celechron/design/rolling_shimmer_text.dart';

import 'package:celechron/page/search/search_view.dart';
import 'course_list/course_list_view.dart';
import 'course_schedule/course_schedule_view.dart';
import 'exam_list/exam_list_view.dart';
import 'grade_detail/grade_detail_view.dart';
import 'practice_score/practice_score_page.dart';
import 'scholar_controller.dart';
import 'package:celechron/page/option/option_controller.dart';
import 'package:celechron/design/dingtalk_sheet.dart';

Future<void> showRefreshResultDialog(
    BuildContext context, List<String?> results) async {
  final messages = results.whereType<String>().toList();
  // 完全成功只通过数据、更新时间和页面状态反馈，不主动打断用户。
  if (messages.isEmpty) return;
  final degraded =
      messages.where(isDegradedRefreshText).toList(growable: false);
  final failures = messages
      .where((message) => !isDegradedRefreshText(message))
      .toList(growable: false);
  if (!context.mounted) return;
  final summaryLines = messages.map((error) {
    final compact =
        shortErrorText(error).replaceAll(RegExp(r'\s+'), ' ').trim();
    final prefix = isDegradedRefreshText(error) ? '降级：' : '失败：';
    final line = '$prefix$compact';
    return line.length <= 100 ? line : '${line.substring(0, 100)}…';
  }).toList();

  await showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(
        '刷新遇到问题：${degraded.length} 项降级，${failures.length} 项失败',
      ),
      content: Text(summaryLines.join('\n')),
      actions: [
        if (messages.isNotEmpty)
          CupertinoDialogAction(
            child: const Text('查看详情'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              showCupertinoDialog<void>(
                context: context,
                builder: (detailContext) => CupertinoAlertDialog(
                  title: const Text('刷新详情'),
                  content: SingleChildScrollView(
                    child: Text(
                      messages.map((error) {
                        final short = shortErrorText(error);
                        final details = detailedErrorText(error);
                        return details == short ? short : '$short\n$details';
                      }).join('\n\n'),
                    ),
                  ),
                  actions: [
                    CupertinoDialogAction(
                      child: const Text('确定'),
                      onPressed: () => Navigator.of(detailContext).pop(),
                    ),
                  ],
                ),
              );
            },
          ),
        CupertinoDialogAction(
          child: const Text('确定'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

/// 全局错误组件（由 main 里的 ErrorWidget.builder 使用）。
///
/// ★ 这个类**绝对不能抛错**。它是在「build 已经出错」之后被调用的；一旦它自己
/// 再抛错，就会变成：
///
///   build 出错 → 错误组件构建 → 又出错 → 错误组件构建 → …
///
/// 的**无限循环**，把 Dart 主 isolate 烧死 —— 表现是界面彻底冻死 + 系统 ANR，
/// 而且因为每一轮都只是在做错误上报，日志里几乎看不到有效信息。
///
/// 本项目曾真实踩中：原实现有两处必然抛错 ——
///   ① 字段初始化器 `Get.put(ScholarController())`：控制器已注册时会抛；
///   ② build 返回 `SliverList`：ErrorWidget 位于 Box 树中，
///      会抛 `RenderSliver cannot be child of RenderBox`。
/// 于是「待办页某个 widget 首次构建出错」被放大成整机卡死。
/// 全局错误日志：把构建错误**攒起来**，而不是画在页面上挡路。
///
/// 以前 `ErrorWidget.builder` 直接画一大块提示，会盖住出错的地方（日程页顶栏的
/// 按钮都被盖掉过）✗ 现在页面上只留一条很矮的提示，内容是这里攒下来的，
/// 点开才看，也可以到「设置」里查 ✓
class AppErrorLog {
  AppErrorLog._();

  /// 最近若干条错误（新的在前）
  static final List<FlutterErrorDetails> entries = <FlutterErrorDetails>[];

  /// 条数变化时通知界面（设置里的入口用它刷新）
  static final ValueNotifier<int> count = ValueNotifier<int>(0);

  static const int maxEntries = 20;

  static void record(FlutterErrorDetails details) {
    try {
      // ErrorWidget.builder 可能在任何页面触发；先把完整异常写入 logcat，
      // 否则页面上的摘要不足以定位真正的构建错误。
      debugPrint('Elychron ErrorWidget: ${details.exceptionAsString()}');
      debugPrintStack(stackTrace: details.stack);
      entries.insert(0, details);
      while (entries.length > maxEntries) {
        entries.removeLast();
      }
      count.value = entries.length;
    } catch (_) {
      // 记录失败绝不能再抛
    }
  }

  static void clear() {
    entries.clear();
    count.value = 0;
  }

  /// 一句话摘要（给列表用）
  static String summaryOf(FlutterErrorDetails details) {
    final text = details.exceptionAsString().split('\n').first.trim();
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }
}

/// 出错位置留下的**一小条**提示（高度固定很矮，不会盖住内容）。
///
/// 点它看详情（含「重新获取数据」的动作，原来那个大卡片上的按钮挪到这里）。
class _AppErrorChip extends StatelessWidget {
  const _AppErrorChip();

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showAppErrorSheet(context),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: CupertinoColors.systemRed.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                  size: 11, color: CupertinoColors.systemRed),
              const SizedBox(width: 4),
              Text('界面这里出了点问题，点开查看',
                  style: TextStyle(fontSize: 11, color: labelColor)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 错误详情面板：列出攒下来的错误 + 「重新获取数据」+「清空」
Future<void> showAppErrorSheet(BuildContext context) {
  // ===== MOD: 换成全 App 统一的钉钉风格面板 =====
  final entries = AppErrorLog.entries;
  return showDingTalkPanel(
    context: context,
    title: '应用错误（${entries.length}）',
    subtitle: entries.isEmpty ? null : '下面是最近 ${entries.length > 5 ? 5 : entries.length} 条',
    children: [
      if (entries.isEmpty)
        const DingTalkPanelNote('暂时没有记录到的错误。')
      else
        for (final entry in entries.take(5))
          DingTalkPanelNote(AppErrorLog.summaryOf(entry)),
    ],
    secondaryActions: [
      DingTalkPanelAction(
        label: '重新获取数据',
        onTap: () async {
          Navigator.of(context).pop();
          try {
            if (!Get.isRegistered<ScholarController>()) return;
            final controller = Get.find<ScholarController>();
            final results = await controller.fetchData();
            if (context.mounted && results.any((result) => result != null)) {
              await showRefreshResultDialog(context, results);
            }
          } catch (_) {}
        },
      ),
      DingTalkPanelAction(
        label: '清空错误记录',
        onTap: () {
          AppErrorLog.clear();
          Navigator.of(context).pop();
        },
      ),
    ],
  );
}

class ScholarErrorHandler extends StatelessWidget {
  final FlutterErrorDetails errorDetails;

  const ScholarErrorHandler({super.key, required this.errorDetails});

  /// 重入保护：构造错误组件期间若又出错，立刻退回最简组件，绝不递归。
  static bool _building = false;

  @override
  Widget build(BuildContext context) {
    if (_building) return const SizedBox.shrink();
    _building = true;
    try {
      return _buildContent(context);
    } catch (_) {
      // 错误组件自身出错：静默降级，绝不二次抛错
      return const SizedBox.shrink();
    } finally {
      _building = false;
    }
  }

  Widget _buildContent(BuildContext context) {
    // ★ 必须是**盒子组件**（不能返回 Sliver），而且必须**尽量不占地方**：
    // 以前这里画一整块「获取数据时遇到问题」的卡片，会把出错位置整个盖住 ——
    // 日程页顶栏被盖掉之后按钮都点不到（用户反馈过）✗
    // 现在只放一条很矮的提示，详情点开才看；错误同时记进 AppErrorLog ✓
    AppErrorLog.record(errorDetails);
    // 不在出错位置渲染任何可见内容：错误只进入设置页的错误中心。
    return const SizedBox.shrink();
  }
}

class ScholarPage extends StatelessWidget {
  ScholarPage({super.key});

  final _scholarController = Get.put(ScholarController());
  final ValueNotifier<bool> _isRefreshing = ValueNotifier(false);

  // 让页内横向列表在桌面端也响应鼠标拖动。外层 PageView 为支持鼠标切页开启了
  // 鼠标拖动，横向列表若不响应鼠标，拖动会漏到 PageView 上造成误切页；
  // 内层可滚动组件在手势竞技中优先，包上后拖动由列表自己消费（触屏行为不变）
  Widget _mouseDraggable(BuildContext context, Widget child) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
        dragDevices: {
          ...ScrollConfiguration.of(context).dragDevices,
          PointerDeviceKind.mouse,
        },
      ),
      child: child,
    );
  }

  Widget _buildGradeBrief(BuildContext context) {
    final optionController =
        Get.find<OptionController>(tag: 'optionController');

    String maskGPA(String s) {
      // 绩点隐藏功能
      if (!optionController.hideHomeGpa) return s;
      return s.replaceAll('.', '').replaceAll(RegExp(r'[\d.]'), '*');
    }

    return RoundRectangleCard(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: Hero(
                        tag: 'gradeBrief',
                        child: RoundRectangleCardWithForehead(
                            foreheadColor: CustomCupertinoDynamicColors
                                .okGreen.darkColor
                                .withValues(alpha: 0.25),
                            forehead: Obx(() => Row(children: [
                                  // University Icon
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 12, top: 6, bottom: 6),
                                    child: Icon(
                                      Icons.school,
                                      color: CupertinoDynamicColor.resolve(
                                          CupertinoColors.label, context),
                                      size: 18,
                                    ),
                                  ),
                                  Padding(
                                      padding: const EdgeInsets.only(
                                          left: 6, top: 6, bottom: 6),
                                      child: Text('成绩',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            overflow: TextOverflow.ellipsis,
                                            color:
                                                CupertinoDynamicColor.resolve(
                                                    CupertinoColors.label,
                                                    context),
                                          ))),
                                  const Spacer(),
                                  // alert icon
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 4, bottom: 4),
                                    child: Icon(
                                      _scholarController
                                                  .durationToLastUpdateGrade
                                                  .inMinutes <
                                              5
                                          ? CupertinoIcons
                                              .check_mark_circled_solid
                                          : CupertinoIcons
                                              .exclamationmark_circle_fill,
                                      color: CupertinoDynamicColor.resolve(
                                          CupertinoColors.label, context),
                                      size: 14,
                                    ),
                                  ),
                                  Padding(
                                      padding: const EdgeInsets.only(
                                          left: 4,
                                          top: 4,
                                          bottom: 4,
                                          right: 16),
                                      child: Text(
                                          _scholarController
                                                      .durationToLastUpdateGrade
                                                      .inMinutes >
                                                  10000000
                                              ? '获取数据时遇到问题'
                                              : '更新于 ${_scholarController.durationToLastUpdateGrade.inMinutes} 分钟前',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            overflow: TextOverflow.ellipsis,
                                            color:
                                                CupertinoDynamicColor.resolve(
                                                    CupertinoColors.label,
                                                    context),
                                          )))
                                ])),
                            onTap: () async =>
                                Navigator.of(context, rootNavigator: true).push(
                                    CupertinoPageRoute(
                                        builder: (context) => GradeDetailPage(),
                                        fullscreenDialog: true)),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Obx(() => TwoLineCard(
                                          title: '五分制',
                                          content: maskGPA(_scholarController
                                              .gpa[0]
                                              .toStringAsFixed(2)),
                                          backgroundColor:
                                              CustomCupertinoDynamicColors
                                                  .cyan)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Obx(() => TwoLineCard(
                                          title: '获得学分',
                                          content: maskGPA(_scholarController
                                              .scholar.credit
                                              .toStringAsFixed(1)),
                                          backgroundColor:
                                              CustomCupertinoDynamicColors
                                                  .peach)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Obx(() => TwoLineCard(
                                          title: '四分制',
                                          content: maskGPA(_scholarController
                                              .gpa[1]
                                              .toStringAsFixed(2)),
                                          extraContent: maskGPA(
                                              _scholarController.gpa[2]
                                                  .toStringAsFixed(2)),
                                          backgroundColor:
                                              CustomCupertinoDynamicColors
                                                  .spring)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Obx(() => TwoLineCard(
                                          title: '主修均绩',
                                          content: maskGPA(_scholarController
                                              .scholar.majorGpaAndCredit[0]
                                              .toStringAsFixed(2)),
                                          backgroundColor:
                                              CustomCupertinoDynamicColors
                                                  .sakura)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Obx(() => TwoLineCard(
                                          title: '主修学分',
                                          content: maskGPA(_scholarController
                                              .scholar.majorGpaAndCredit[1]
                                              .toStringAsFixed(1)),
                                          backgroundColor:
                                              CustomCupertinoDynamicColors
                                                  .sand)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Obx(() => TwoLineCard(
                                          title: '百分制',
                                          content: maskGPA(_scholarController
                                              .gpa[3]
                                              .toStringAsFixed(2)),
                                          backgroundColor:
                                              CustomCupertinoDynamicColors
                                                  .magenta)),
                                    ),
                                  ],
                                ),
                              ],
                            )))),
              ],
            ),
          ],
        ));
  }

  Widget _buildSemester(BuildContext context) {
    return RoundRectangleCard(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: RoundRectangleCardWithForehead(
                        animate: false,
                        foreheadColor: CustomCupertinoDynamicColors
                            .cyan.darkColor
                            .withValues(alpha: 0.25),
                        forehead: Obx(() => Row(children: [
                              // University Icon
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 12, top: 6, bottom: 6),
                                child: Icon(
                                  Icons.calendar_month_rounded,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.label, context),
                                  size: 18,
                                ),
                              ),
                              Padding(
                                  padding: const EdgeInsets.only(
                                      left: 6, top: 6, bottom: 6),
                                  child: Text('课程',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        overflow: TextOverflow.ellipsis,
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.label, context),
                                      ))),
                              const Spacer(),
                              // alert icon
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4, bottom: 4),
                                child: Icon(
                                  _scholarController.durationToLastUpdateCourse
                                              .inMinutes <
                                          5
                                      ? CupertinoIcons.check_mark_circled_solid
                                      : CupertinoIcons
                                          .exclamationmark_circle_fill,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.label, context),
                                  size: 14,
                                ),
                              ),
                              Padding(
                                  padding: const EdgeInsets.only(
                                      left: 4, top: 4, bottom: 4, right: 16),
                                  child: Text(
                                      _scholarController
                                                  .durationToLastUpdateCourse
                                                  .inMinutes >
                                              10000000
                                          ? '获取数据时遇到问题'
                                          : '更新于 ${_scholarController.durationToLastUpdateCourse.inMinutes} 分钟前',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        overflow: TextOverflow.ellipsis,
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.label, context),
                                      )))
                            ])),
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            MultipleColumns(
                              contents: [
                                Text(
                                    _scholarController
                                        .selectedSemester.courses.length
                                        .toString(),
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .navTitleTextStyle
                                        .copyWith(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                                Text(
                                    _scholarController
                                        .selectedSemester.courseCredit
                                        .toString(),
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .navTitleTextStyle
                                        .copyWith(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                                Text(
                                    _scholarController
                                        .selectedSemester.examCount
                                        .toString(),
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .navTitleTextStyle
                                        .copyWith(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                              ],
                              titles: const ['课程', '学分', '考试'],
                              onTaps: [
                                () => Navigator.of(context, rootNavigator: true)
                                    .push(CupertinoPageRoute(
                                        builder: (context) => CourseListPage(
                                            initialSemesterName:
                                                _scholarController
                                                    .selectedSemester.name),
                                        title: '课程')),
                                null,
                                () => Navigator.of(context, rootNavigator: true)
                                    .push(CupertinoPageRoute(
                                        builder: (context) => ExamListPage(
                                            initialSemesterName:
                                                _scholarController
                                                    .selectedSemester.name),
                                        title: '考试'))
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TwoLineCard(
                                      animate: true,
                                      // With CupertinoPageTransition
                                      onTap: () => Navigator.of(context,
                                                  rootNavigator: true)
                                              .push(
                                            CupertinoPageRoute(
                                              builder: (context) =>
                                                  CourseSchedulePage(
                                                      _scholarController
                                                          .selectedSemester
                                                          .name,
                                                      true),
                                              title: '课表',
                                            ),
                                          ),
                                      title:
                                          '${_scholarController.selectedSemester.firstHalfName}学期课时',
                                      content:
                                          '${_scholarController.selectedSemester.firstHalfSessionCount}节/两周',
                                      backgroundColor: _scholarController
                                                  .selectedSemester.name[9] ==
                                              '春'
                                          ? CustomCupertinoDynamicColors.spring
                                          : CustomCupertinoDynamicColors.autumn,
                                      withColoredFont: true),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TwoLineCard(
                                      animate: true,
                                      onTap: () => Navigator.of(context,
                                                  rootNavigator: true)
                                              .push(
                                            CupertinoPageRoute(
                                              builder: (context) =>
                                                  CourseSchedulePage(
                                                      _scholarController
                                                          .selectedSemester
                                                          .name,
                                                      false),
                                              title: '课表',
                                            ),
                                          ),
                                      title:
                                          '${_scholarController.selectedSemester.secondHalfName}学期课时',
                                      content:
                                          '${_scholarController.selectedSemester.secondHalfSessionCount}节/两周',
                                      backgroundColor: _scholarController
                                                  .selectedSemester.name[9] ==
                                              '春'
                                          ? CustomCupertinoDynamicColors.summer
                                          : CustomCupertinoDynamicColors.winter,
                                      withColoredFont: true),
                                ),
                              ],
                            ),
                          ],
                        ))),
              ],
            ),
          ],
        ));
  }

  Widget _buildTodos(BuildContext context) {
    return RoundRectangleCard(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: RoundRectangleCardWithForehead(
                        animate: false,
                        foreheadColor: CustomCupertinoDynamicColors
                            .magenta.darkColor
                            .withValues(alpha: 0.25),
                        forehead: Obx(() => Row(children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 12, top: 6, bottom: 6),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.label, context),
                                  size: 18,
                                ),
                              ),
                              Padding(
                                  padding: const EdgeInsets.only(
                                      left: 6, top: 6, bottom: 6),
                                  child: Text('作业',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        overflow: TextOverflow.ellipsis,
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.label, context),
                                      ))),
                              const Spacer(),
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 4, bottom: 4),
                                child: Icon(
                                  _scholarController
                                              .durationToLastUpdateHomework
                                              .inMinutes <
                                          5
                                      ? CupertinoIcons.check_mark_circled_solid
                                      : CupertinoIcons
                                          .exclamationmark_circle_fill,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.label, context),
                                  size: 14,
                                ),
                              ),
                              Padding(
                                  padding: const EdgeInsets.only(
                                      left: 4, top: 4, bottom: 4, right: 16),
                                  child: Text(
                                      _scholarController
                                                  .durationToLastUpdateHomework
                                                  .inMinutes >
                                              10000000
                                          ? '获取数据时遇到问题'
                                          : '更新于 ${_scholarController.durationToLastUpdateHomework.inMinutes} 分钟前',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        overflow: TextOverflow.ellipsis,
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.label, context),
                                      )))
                            ])),
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            MultipleColumns(
                              contents: [
                                Text(_scholarController.todos.length.toString(),
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .navTitleTextStyle
                                        .copyWith(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                                Text(
                                    _scholarController.todosInOneDay.length
                                        .toString(),
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .navTitleTextStyle
                                        .copyWith(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                                Text(
                                    _scholarController.todosInOneWeek.length
                                        .toString(),
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .navTitleTextStyle
                                        .copyWith(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                              ],
                              titles: const ["总计", "一天内", "本周截止"],
                              onTaps: [() {}, () {}, () {}],
                            ),
                            const SizedBox(height: 16),
                            if (_scholarController.todos.isNotEmpty)
                              SizedBox(
                                  height: 102,
                                  child: _mouseDraggable(
                                      context,
                                      ListView.separated(
                                          scrollDirection: Axis.horizontal,
                                          itemCount:
                                              _scholarController.todos.length,
                                          separatorBuilder: (context, index) =>
                                              const SizedBox(width: 8),
                                          itemBuilder: (context, index) {
                                            final todo =
                                                _scholarController.todos[index];
                                            return SizedBox(
                                                width: 200,
                                                child: TodoCard(todo: todo));
                                          })))
                          ],
                        ))),
              ],
            ),
          ],
        ));
  }

  Widget _buildPractice(BuildContext context) {
    return RoundRectangleCard(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: RoundRectangleCardWithForehead(
                        animate: false,
                        foreheadColor: CustomCupertinoDynamicColors
                            .peach.darkColor
                            .withValues(alpha: 0.25),
                        forehead: Obx(() => Row(children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 12, top: 6, bottom: 6),
                                child: Icon(
                                  Icons.star_rounded,
                                  color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.label, context),
                                  size: 18,
                                ),
                              ),
                              Padding(
                                  padding: const EdgeInsets.only(
                                      left: 6, top: 6, bottom: 6),
                                  child: Text('实践',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        overflow: TextOverflow.ellipsis,
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.label, context),
                                      ))),
                              const Spacer(),
                              if (!_scholarController
                                  .scholar.isPracticeScoresGet)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 4, bottom: 4),
                                  child: Icon(
                                    CupertinoIcons.exclamationmark_circle_fill,
                                    color: CupertinoDynamicColor.resolve(
                                        CupertinoColors.label, context),
                                    size: 14,
                                  ),
                                ),
                              if (!_scholarController
                                  .scholar.isPracticeScoresGet)
                                Padding(
                                    padding: const EdgeInsets.only(
                                        left: 4, top: 4, bottom: 4, right: 16),
                                    child: Text('获取实践记点时遇到问题',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          overflow: TextOverflow.ellipsis,
                                          color: CupertinoDynamicColor.resolve(
                                              CupertinoColors.label, context),
                                        ))),
                            ])),
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            Obx(
                              () => PracticeScoreColumns(
                                scholar: _scholarController.scholar,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ))),
              ],
            ),
          ],
        ));
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
        /*backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),*/
        child: CustomScrollView(
      slivers: [
        SliverPinnedToBoxAdapter(
            child: Container(
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(
                CupertinoColors.systemBackground, context),
            /*boxShadow: [
              BoxShadow(
                color: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemGrey5, context),
                offset: const Offset(0, 0),
                blurRadius: 4,
              ),
            ],
            borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16)),*/
          ),
          child: Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: 4,
                  top: 8 + MediaQuery.of(context).padding.top),
              child: Column(children: [
                Row(
                  children: [
                    const SizedBox(width: 2),
                    Text(
                      '学业',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .navLargeTitleTextStyle
                          .copyWith(fontSize: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoSearchTextField(
                        placeholder: '搜索课程、事项...',
                        placeholderStyle: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .copyWith(
                                color: CupertinoColors.systemGrey,
                                height: 1.25,
                                fontSize: 18),
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .textStyle
                            .copyWith(height: 1.25, fontSize: 18),
                        borderRadius: BorderRadius.circular(12),
                        itemColor: CupertinoColors.systemGrey,
                        itemSize: 20,
                        suffixInsets:
                            const EdgeInsetsDirectional.fromSTEB(0, 0, 5, 0),
                        prefixInsets:
                            const EdgeInsetsDirectional.fromSTEB(10, 0, 0, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                        onTap: () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.of(context, rootNavigator: true).push(
                              CupertinoPageRoute(
                                  builder: (context) => SearchPage()));
                        },
                        focusNode: AlwaysDisabledFocusNode(),
                        // Do not popup the keyboard
                      ),
                    ),
                    if (PlatformFeatures.isDesktop)
                      ValueListenableBuilder(
                          valueListenable: _isRefreshing,
                          builder: (context, isRefreshing, child) =>
                              CupertinoButton(
                                onPressed: isRefreshing
                                    ? null
                                    : () async {
                                        _isRefreshing.value = true;
                                        late final List<String?> results;
                                        try {
                                          results = await _scholarController
                                              .fetchData();
                                        } finally {
                                          _isRefreshing.value = false;
                                        }
                                        if (context.mounted &&
                                            results.any(
                                                (result) => result != null)) {
                                          await showRefreshResultDialog(
                                              context, results);
                                        }
                                      },
                                child: isRefreshing
                                    ? const CupertinoActivityIndicator()
                                    : Icon(
                                        CupertinoIcons.refresh,
                                        color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.systemBlue,
                                            context),
                                        size: 20,
                                      ),
                              ))
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 30,
                        child: _mouseDraggable(
                          context,
                          Obx(
                            () => ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _scholarController.semesters.length,
                              itemBuilder: (context, index) {
                                final semester =
                                    _scholarController.semesters[index];
                                return Stack(
                                  children: [
                                    Obx(
                                      () => AnimateButton(
                                        text:
                                            '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}',
                                        onTap: () {
                                          _scholarController
                                              .semesterIndex.value = index;
                                          _scholarController.semesterIndex
                                              .refresh();
                                        },
                                        backgroundColor: _scholarController
                                                    .semesterIndex.value ==
                                                index
                                            ? CustomCupertinoDynamicColors.cyan
                                            : CupertinoColors.systemFill,
                                      ),
                                    ),
                                    const SizedBox(width: 90),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // 桌面端刷新超过 5 秒后的状态条：小转圈 + 滚动文案，随刷新结束收起。
                // 移动端的状态文案由下方 CupertinoSliverRefreshControl 的 builder 展示
                if (PlatformFeatures.isDesktop)
                  Obx(() {
                    final message =
                        _scholarController.refreshStatusMessage.value;
                    return AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      // AnimatedSwitcher 让收起时末条文案先淡出、条带再合拢，
                      // 而不是内容瞬间消失
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: message == null
                            ? const SizedBox(
                                key: ValueKey('refreshStatusStripEmpty'),
                                width: double.infinity)
                            : Padding(
                                key: const ValueKey('refreshStatusStrip'),
                                padding:
                                    const EdgeInsets.only(top: 6, bottom: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const CupertinoActivityIndicator(radius: 7),
                                    const SizedBox(width: 6),
                                    Flexible(
                                        child: RollingShimmerText(message)),
                                  ],
                                ),
                              ),
                      ),
                    );
                  }),
                const SizedBox(height: 4),
                Divider(
                  thickness: 0,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.separator, context),
                  height: 14,
                ),
              ])),
        )),
        if (_scholarController.scholar.isLogan)
          CupertinoSliverRefreshControl(
            // 复刻原生转圈，刷新超过 5 秒后在其右侧滚动展示状态文案。
            // Obx 是必需的：刷新驻留期间 sliver 高度不变、builder 不会被重调，
            // 文案更新只能靠响应式重建
            builder: (context, refreshState, pulledExtent,
                    refreshTriggerPullDistance, refreshIndicatorExtent) =>
                Obx(() => RefreshStatusIndicator(
                      refreshState: refreshState,
                      pulledExtent: pulledExtent,
                      refreshTriggerPullDistance: refreshTriggerPullDistance,
                      refreshIndicatorExtent: refreshIndicatorExtent,
                      message: _scholarController.refreshStatusMessage.value,
                    )),
            onRefresh: () async {
              final results = await _scholarController.fetchData();
              if (context.mounted && results.any((result) => result != null)) {
                await showRefreshResultDialog(context, results);
              }
            },
          ),
        SliverToBoxAdapter(
          child: Obx(() {
            if (_scholarController.scholar.semesters.isNotEmpty) {
              return Padding(
                padding: EdgeInsets.only(
                    top: 8,
                    right: 16,
                    left: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 4),
                child: Column(
                  children: _scholarController.scholar.isGrs
                      ? [
                          const SizedBox(height: 12),
                          _buildSemester(context),
                          const SizedBox(height: 12),
                          Divider(
                            thickness: 0,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.separator, context),
                            height: 14,
                          ),
                          const SizedBox(height: 12),
                          _buildTodos(context),
                        ]
                      : [
                          _buildGradeBrief(context),
                          const SizedBox(height: 12),
                          Divider(
                            thickness: 0,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.separator, context),
                            height: 14,
                          ),
                          const SizedBox(height: 12),
                          _buildSemester(context),
                          const SizedBox(height: 12),
                          Divider(
                            thickness: 0,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.separator, context),
                            height: 14,
                          ),
                          const SizedBox(height: 12),
                          _buildTodos(context),
                          const SizedBox(height: 12),
                          Divider(
                            thickness: 0,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.separator, context),
                            height: 14,
                          ),
                          const SizedBox(height: 12),
                          _buildPractice(context),
                          const SizedBox(height: 20),
                        ],
                ),
              );
            } else {
              return SizedBox(
                  height: 500,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(),
                        Icon(
                          _scholarController.scholar.isLogan
                              ? CupertinoIcons.arrow_clockwise
                              : CupertinoIcons.person_crop_circle,
                          size: 48,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                            _scholarController.scholar.isLogan
                                ? '下拉刷新以获取数据'
                                : '未登录',
                            style:
                                CupertinoTheme.of(context).textTheme.textStyle),
                        if (_scholarController.scholar.isLogan)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '离线数据将在同步失败时自动使用',
                              style: TextStyle(
                                fontSize: 13,
                                color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.secondaryLabel, context),
                              ),
                            ),
                          ),
                        const Spacer()
                      ]));
            }
          }),
        ),
      ],
    ));
  }
}

class AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
}
