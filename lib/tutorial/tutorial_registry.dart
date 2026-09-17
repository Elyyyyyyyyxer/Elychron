import 'package:celechron/tutorial/modules/tutorial_basics.dart';
import 'package:celechron/tutorial/modules/tutorial_courses.dart';
import 'package:celechron/tutorial/modules/tutorial_data.dart';
import 'package:celechron/tutorial/modules/tutorial_focus.dart';
import 'package:celechron/tutorial/modules/tutorial_setup.dart';
import 'package:celechron/tutorial/modules/tutorial_tasks.dart';
import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程注册表 ============
///
/// **加一篇教程只需要两步**：
/// 1. 在 `lib/tutorial/modules/` 下新建一个文件，导出 `Tutorial`（参考 `tutorial_tasks.dart`）；
/// 2. 在这个文件的 [_all] 里加一行。
///
/// 其余全自动：教程中心会按分组列出它、帮助按钮能按 id 打开它、
/// 首用提示走同一套"已看过"记录。
///
/// 注册表还负责**完整性自查**（见 [problems]）：id 重复、没步骤、
/// 图片路径写错之类的问题，测试里会直接报出来，不用等用户点进去才发现。
class TutorialRegistry {
  TutorialRegistry._();

  /// 全部教程。**这里是唯一的登记处。**
  static const List<Tutorial> _all = <Tutorial>[
    // ===== 入门 =====
    // 顺序 = 「教程中心」的展示顺序：用「配置」打头（那是用之前要做的事），
    // 然后是待办、数据两篇。往这里加一行就多一篇教程。
    tutorialSetup,
    tutorialBasics,
    tutorialTasks,
    tutorialCourses,
    tutorialFocus,
    tutorialData,

    // 以后加功能时往这里加，例如：
    // tutorialCalendar,
    // tutorialFocus,
    // tutorialAi,
    // tutorialSync,
  ];

  /// 全部教程
  static List<Tutorial> get all => List.unmodifiable(_all);

  /// 按 id 取（找不到返回 null，调用方自己决定要不要提示）
  static Tutorial? byId(String id) {
    for (final tutorial in _all) {
      if (tutorial.id == id) return tutorial;
    }
    return null;
  }

  /// 按分组聚合（教程中心的展示顺序）：组内按注册顺序
  static Map<TutorialGroup, List<Tutorial>> get grouped {
    final result = <TutorialGroup, List<Tutorial>>{};
    for (final group in TutorialGroup.values) {
      final items = _all.where((t) => t.group == group).toList();
      if (items.isNotEmpty) result[group] = items;
    }
    return result;
  }

  /// 完整性自查：返回发现的问题（空列表 = 没问题）。
  ///
  /// 放在测试里跑（`test/tutorial_test.dart`），也可以在调试构建里打印出来。
  static List<String> problems() {
    final issues = <String>[];
    final seenIds = <String>{};

    for (final tutorial in _all) {
      if (tutorial.id.trim().isEmpty) {
        issues.add('有教程的 id 是空的（标题：${tutorial.title}）');
      } else if (!seenIds.add(tutorial.id)) {
        issues.add('教程 id 重复：${tutorial.id}');
      }
      if (tutorial.title.trim().isEmpty) {
        issues.add('教程 ${tutorial.id} 没有标题');
      }
      if (tutorial.summary.trim().isEmpty) {
        issues.add('教程 ${tutorial.id} 没有一句话说明');
      }
      if (tutorial.steps.isEmpty) {
        issues.add('教程 ${tutorial.id} 一步都没有');
      }
      if (tutorial.contentVersion < 1) {
        issues.add('教程 ${tutorial.id} 的 contentVersion 应该 >= 1');
      }
      for (var i = 0; i < tutorial.steps.length; i++) {
        final step = tutorial.steps[i];
        switch (step) {
          case TutorialTextStep(:final body):
            // ⚠️ 这里**不再要求每步都有标题**（2026-09-17）：
            // 教程文案是用户手写的，"同一节的续页"本来就不该硬编一个小标题 ——
            // 空标题的步骤渲染器会直接不画标题行。只要求整篇第一步有标题。
            if (i == 0 && body.isEmpty) {
              issues.add('教程 ${tutorial.id} 第 1 步没有正文');
            }
            if (body.isEmpty) {
              issues.add('教程 ${tutorial.id} 第 ${i + 1} 步没有正文');
            }
          case TutorialTipsStep(:final tips):
            if (tips.isEmpty) {
              issues.add('教程 ${tutorial.id} 第 ${i + 1} 步的清单是空的');
            }
          case TutorialImageStep(:final assets):
            if (assets.isEmpty) {
              issues.add('教程 ${tutorial.id} 第 ${i + 1} 步没有图片');
            }
            for (final asset in assets) {
              if (!asset.startsWith('assets/')) {
                issues.add(
                    '教程 ${tutorial.id} 第 ${i + 1} 步的图片路径要以 assets/ 开头：$asset');
              }
            }
          case TutorialCompareStep(:final left, :final right):
            if (left.isEmpty || right.isEmpty) {
              issues.add('教程 ${tutorial.id} 第 ${i + 1} 步的对比两栏不能有空的一边');
            }
          case TutorialActionStep(:final buttonLabel):
            if (buttonLabel.trim().isEmpty) {
              issues.add('教程 ${tutorial.id} 第 ${i + 1} 步的行动按钮没有文字');
            }
        }
      }
    }
    return issues;
  }

  /// 某篇教程里用到的全部图片路径（给"资源是否齐全"的自查用）
  static List<String> assetsOf(Tutorial tutorial) => [
        for (final step in tutorial.steps)
          if (step is TutorialImageStep) ...step.assets,
      ];
}
