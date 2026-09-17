/// ============ 教程模块：数据模型 ============
///
/// ## 设计目标
///
/// 后面的功能会一直加，所以教程必须是**模块化、可扩展**的：
///
/// 1. **加一篇教程 = 新建一个文件 + 注册表加一行**，不需要碰任何渲染/状态代码；
/// 2. **教程内容只写数据**（标题、段落、图片路径…），不写 UI 代码 ——
///    样式统一由播放器决定，将来改版只改一处；
/// 3. **步骤类型可扩展**：[TutorialStep] 是 `sealed` 家族，
///    新增一种步骤 = 新增一个子类 + 在渲染器里补一个 case，
///    Dart 的**穷尽性检查会在编译期**提醒所有没处理的地方（这是选 sealed 而不是
///    "一个大而全的字段结构"的原因）；
/// 4. **文案就在模块文件里**（本仓库没有独立的语言文件，用户想手改文案就改那个文件）。
///
/// ## 一篇教程长什么样
///
/// ```dart
/// Tutorial(
///   id: 'tasks',                    // 稳定标识，改名会让"已看过"记录失效
///   title: '待办',
///   summary: '截止 / 活动 / 提醒 / 备忘四种类型怎么选',
///   group: TutorialGroup.tasks,
///   steps: [
///     TutorialTextStep(title: '…', body: ['…']),
///     TutorialTipsStep(title: '…', tips: ['…']),
///     TutorialImageStep(asset: 'assets/tutorial/tasks/type.png', caption: '…'),
///   ],
/// )
/// ```
library;

/// 教程分组：只影响"教程中心"的展示顺序与分节，功能上无意义
enum TutorialGroup {
  basics('入门'),
  tasks('待办'),
  calendar('课表与日程'),
  focus('专注'),
  ai('AI 智能助手'),
  data('数据与备份'),
  sync('多端与同步'),
  advanced('进阶');

  const TutorialGroup(this.label);

  /// 分节标题（界面上显示）
  final String label;
}

/// 这篇教程对谁可见 —— 给"登录后才有的功能"和"开关类功能"留的口子
enum TutorialAudience {
  /// 谁都能看
  everyone,

  /// 只有登录后才看得到（未登录时在教程中心隐藏）
  loggedInOnly,
}

/// 教程里一步能跳去的目标。
///
/// 为什么用枚举而不是回调：回调会让"内容文件"里出现代码，
/// 破坏"内容是纯数据、样式与跳转集中在播放器"的约定。
/// 需要新目标时：加一个枚举值 + 在 `tutorial_entry.dart` 的映射里补一行。
enum TutorialTarget {
  taskList,
  calendar,
  focus,
  aiSettings,
  dataSection,
  settings,
}

/// 一篇教程
class Tutorial {
  /// 稳定标识（**改名会让用户的"已看过"记录失效**，尽量别改）
  final String id;

  /// 标题（教程中心与播放器顶栏）
  final String title;

  /// 一句话说明（教程中心列表里显示）
  final String summary;

  final TutorialGroup group;
  final TutorialAudience audience;
  final List<TutorialStep> steps;

  /// 内容版本：**内容大改后 +1 可以让"已看过"的用户重新看到一次**
  /// （比如把一篇教程从 3 步扩到 10 步时）
  final int contentVersion;

  /// 是否可以被"首次使用自动弹一次"（默认 true；纯查阅类的教程设 false）
  final bool showOnFirstUse;

  const Tutorial({
    required this.id,
    required this.title,
    required this.summary,
    required this.steps,
    this.group = TutorialGroup.basics,
    this.audience = TutorialAudience.everyone,
    this.contentVersion = 1,
    this.showOnFirstUse = true,
  });

  /// 给"已看过"判断用：内容版本变了就算没看过（会重新提示一次）
  String get seenKey => '$id@v$contentVersion';
}

/// ============ 步骤类型（sealed：新增类型会有编译期提醒）============

/// 教程里的一步。想加新类型就继承它，然后在 `steps/step_renderers.dart`
/// 的 switch 里补一个分支（漏了会编译报错）。
sealed class TutorialStep {
  const TutorialStep();
}

/// 纯文字：标题 + 若干段落
class TutorialTextStep extends TutorialStep {
  final String title;

  /// 段落列表（每项一段；不要写超长段落，手机上很难读）
  final List<String> body;

  const TutorialTextStep({required this.title, required this.body});
}

/// 要点清单：适合"注意事项 / 小技巧 / 能做与不能做"
class TutorialTipsStep extends TutorialStep {
  final String title;
  final List<String> tips;

  /// 是否当成"警告"来配色（橙色调），默认普通提示
  final bool warning;

  const TutorialTipsStep({
    required this.title,
    required this.tips,
    this.warning = false,
  });
}

/// 一张图（截图 / 示意图）+ 可选的标题与说明
///
/// - 图片放在 `assets/tutorial/<教程id>/` 下（`pubspec.yaml` 已声明整个 `assets/`，
///   所以**不用改 pubspec**）；
/// - **一步放一张**（想放多张就多写几步 —— 教程的约定是"一步只说一件事"）；
/// - 显示时按屏幕宽度等比缩放，但**限制最大高度**：手机截图是 1080×2376 这种竖长条，
///   直接铺满会把一屏塞死。**点一下可以全屏放大**（可捏合），
///   因为教程里最常见的需求就是"看清那个按钮到底在哪"；
/// - 图还没准备好时会显示占位框并写出期望路径 ——
///   "框架先搭、内容后补"的过程里，教程仍然可以走通、也能看出缺哪张图。
class TutorialImageStep extends TutorialStep {
  /// 图片路径（以 `assets/` 开头）
  final String asset;

  /// 图上面的标题（可空；空则不显示标题行）
  final String title;

  /// 图下面的说明（可空）
  final String? caption;

  const TutorialImageStep({required this.asset, this.title = '', this.caption});
}

/// 两栏对比：适合"以前 / 现在""官方版 / Elychron"这类说明
class TutorialCompareStep extends TutorialStep {
  final String title;
  final String leftLabel;
  final List<String> left;
  final String rightLabel;
  final List<String> right;

  const TutorialCompareStep({
    required this.title,
    required this.leftLabel,
    required this.left,
    required this.rightLabel,
    required this.right,
  });
}

/// 行动步：告诉用户"现在去试试"，并给一个能直接跳过去的按钮
class TutorialActionStep extends TutorialStep {
  final String title;
  final String body;
  final String buttonLabel;
  final TutorialTarget target;

  const TutorialActionStep({
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.target,
  });
}
