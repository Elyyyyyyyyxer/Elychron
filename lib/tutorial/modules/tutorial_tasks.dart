import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程内容：待办 ============
///
/// ## 这就是"加一篇教程"的完整样子
///
/// 1. 复制这个文件，改名（例如 `tutorial_focus.dart`）；
/// 2. 改下面的 `Tutorial(...)`；
/// 3. 在 `lib/tutorial/tutorial_registry.dart` 的 `_all` 里加一行。
///
/// 不需要碰播放器、不需要改 pubspec（图片放 `assets/tutorial/<id>/` 就会被打包）。
///
/// ## 写内容时的几条约定
///
/// - **一步只说一件事**，宁可多几步，也不要把手机屏幕塞满；
/// - 段落之间用 `body: ['第一段', '第二段']`，不要在一个字符串里换行；
/// - 截图放 `assets/tutorial/tasks/xxx.png`；
///   图还没准备好也没关系 —— 播放器会显示占位框并写出期望路径；
/// - 想跳去某个功能用 [TutorialActionStep]。
const Tutorial tutorialTasks = Tutorial(
  id: 'tasks',
  title: '待办：四种类型怎么选',
  summary: '截止 / 活动 / 提醒 / 备忘，选错类型提醒时间会不对',
  group: TutorialGroup.tasks,
  steps: [
    TutorialTextStep(
      title: '先选对类型',
      body: [
        '新建待办时第一件事是选类型。它决定"什么时候提醒你"，选错了提醒时间会差很远。',
        '四种类型分别对应：有截止时刻的、占一段时间的、只要某个时刻提醒的、以及只想记下来的。',
      ],
    ),
    TutorialTipsStep(
      title: '四种类型的分工',
      tips: [
        '截止：作业、报告这类"到点必须交"的事。提醒锚在截止时刻。',
        '活动：讲座、会议、上课这类占一段时间的事。提醒锚在开始时刻。',
        '提醒：只在某个时刻提醒一次，不占时间（比如"下午三点给老师发消息"）。',
        '备忘：只记下来、不提醒（比如"记得买牙膏"）。',
      ],
    ),
    TutorialImageStep(
      assets: <String>['assets/tutorial/tasks/types.png'],
      title: '新建页长这样',
      caption: '最上面那一行就是类型；下面填标题、时间、地点。点图可以放大看。',
    ),
    TutorialTipsStep(
      title: '提醒提前量',
      warning: false,
      tips: [
        '设置里的"默认提醒提前量"是所有新待办的默认值（默认提前 30 分钟）。',
        '单条待办可以单独改：详情页 → 提醒。',
        '改成"准时"就是到点才响。',
      ],
    ),
    TutorialActionStep(
      title: '去试一条',
      body: '建一条"明天交作业"试试：类型选截止、时间填明天 23:59，看看提醒时间是不是自动算好了。',
      buttonLabel: '打开待办页',
      target: TutorialTarget.taskList,
    ),
  ],
);
