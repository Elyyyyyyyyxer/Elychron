import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程内容：专注模式 ============
///
/// **内容来源**：用户手写的 `docs/GUIDE_V1.4.1.md`「三、专注模式」一节。
/// 六张图都是我按稿子里的【图片】（提示…）在真机上拍的（`assets/tutorial/focus/`）：
/// 专注页 / 选择待办 / 命名弹窗 / 工作中 / 暂停效果 / 暂停后的黄色提示卡。
///
/// 稿子里特别点出的一句"如果自由专注开始的时间落在某节课上，会自动归类进那节课"，
/// 正是 2026-09-17 那轮修的东西 —— 所以这里也把"页面会告诉你这次算不算课程"写进步骤里。
const Tutorial tutorialFocus = Tutorial(
  id: 'focus',
  title: '专注模式：把时间记下来',
  summary: '开始专注、绑定专注对象、暂停与继续、看专注记录',
  group: TutorialGroup.focus,
  steps: [
    TutorialTextStep(
      title: '为什么要有专注模式',
      body: [
        '为了更精细地管理时间、了解时间消耗，Elychron 增加了专注模式。',
        '这个模式下手机会自动进入免打扰状态，辅助你专心工作。',
        '同时 Elychron 会认真记录你工作的时间 —— 找到时间泄露的缺口，补起来就很方便了！',
      ],
    ),
    TutorialTextStep(
      title: '专注页面长这样',
      body: ['包含三个部分：开始专注、专注对象、专注记录。'],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/focus/home.png',
      caption: '专注页：大圆是开始专注，中间是专注对象，下面是记录',
    ),
    TutorialTextStep(
      title: '一、专注对象',
      body: [
        '专注对象选择器会把专注的时长绑定到具体的课程、待办或是任意指定的事情上。',
        '选「选择待办」，可以把这段专注记到某条待办上。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/focus/pick-task.png',
      caption: '选择待办：挑一条就好',
    ),
    TutorialTextStep(
      title: '也可以临时命名一个项目',
      body: ['选「命名项目」，可以临时新建一个项目，随手记录时间。'],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/focus/name-project.png',
      caption: '命名专注项目（比如「敲代码」「看书」「写报告」）',
    ),
    TutorialTextStep(
      title: '什么都不选 = 自由专注',
      body: [
        '如果什么都不选择，就会进入自由专注状态，时长以「专注」这个名字计算。',
        '⭐ 如果自由专注开始的时间正好落在某节课上，**会自动归类进那节课** ——',
        '开始专注之前，页面会直接告诉你这次算不算：',
        '·「本次专注会计入《××》」·「本次专注不归属课程（开始时课表里没有课）」·「自动计入课程：已关闭」。',
      ],
    ),
    TutorialTextStep(
      title: '二、开始专注',
      body: [
        '开始专注后，会自动进入工作-休息循环（默认 45 分钟工作 / 5 分钟休息，可在设置里改）。',
        '到休息时间时，Elychron 会发通知告诉你。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/focus/working.png',
      caption: '工作中：中间的圆是倒计时，下面写着这一轮算不算课程',
    ),
    TutorialTextStep(
      title: '随时可以暂停',
      body: ['你也可以随时选择暂停 —— 停下来的这段时间不会被算进专注时长。'],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/focus/paused-effect.png',
      caption: '暂停后，按钮会变成「继续」',
    ),
    TutorialTextStep(
      title: '暂停之后可以去干别的',
      body: [
        '这个时候就可以切到 Elychron 的其他页面啦，临时想到什么待办非常实用！',
        '再次回到专注页，会看到一条提示，点「继续」就能接着刚才的进度。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/focus/paused-card.png',
      caption: '有一次专注还没结束 —— 继续 / 结束并结算',
    ),
    TutorialTextStep(
      title: '三、专注记录',
      body: [
        '打开专注记录，可以看到历史上所有的专注时长。',
        '可以按标签、待办、星期分类，统计起来非常方便；',
        '按课程看的时候，只要开始专注时正在上课，自由专注也会算到那门课上。',
      ],
    ),
    TutorialTextStep(
      title: '你专注了吗？',
      body: ['好好利用专注模式吧！'],
    ),
  ],
);
