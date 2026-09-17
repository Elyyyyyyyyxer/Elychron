import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程内容：专注模式 ============
///
/// **内容全部来自用户手写的 `docs/GUIDE_V1.4.1.md`「三、专注模式」一节**，一句话都没改。
/// 六张图按他稿子里的【图片】（提示…）在真机上拍：
/// 专注页 / 选择待办 / 命名弹窗（"显示命名弹窗"）/ 工作中 / 暂停效果（"具体的暂停效果"）/
/// 暂停提示卡（"只用展示那个黄色的提示卡片" —— 现在这张卡是浅粉底，形态没变）。
const Tutorial tutorialFocus = Tutorial(
  id: 'focus',
  title: '专注模式',
  summary: '为了更精细地管理时间、了解时间消耗，Elychron增加了专注模式',
  group: TutorialGroup.focus,
  steps: [
    TutorialImageStep(
      title: '专注模式',
      body: <String>[
        '为了更精细地管理时间、了解时间消耗，Elychron增加了专注模式。',
        '这个模式下，手机会自动进入免打扰状态，辅助你专心工作。',
        '同时，Elychron会认真记录你工作的时间。找到时间泄露的缺口，补起来就很方便了！',
        '这是专注模式的页面，包含开始专注、专注对象、专注记录三个部分。',
      ],
      assets: <String>['assets/tutorial/focus/home.png'],
    ),
    TutorialImageStep(
      title: '专注对象',
      body: <String>[
        '专注对象选择器会将专注的时长绑定到具体的课程、待办或是任意指定的事情上。',
        '选择待办，可以指定被专注的待办。',
      ],
      assets: <String>['assets/tutorial/focus/pick-task.png'],
    ),
    TutorialImageStep(
      body: <String>['选择命名项目，可以临时新建一个项目，随手记录时间。'],
      assets: <String>['assets/tutorial/focus/name-project.png'],
    ),
    TutorialTextStep(
      title: '',
      body: [
        '如果什么都不选择，则会进入自由专注状态。这个状态下的时长会以“专注”名字计算',
        '当然，如果自由专注开始的时间落在某节课上，会自动归类进那节课哦',
      ],
    ),
    TutorialImageStep(
      title: '开始专注',
      body: <String>['开始专注后，会自动进入工作-休息循环。'],
      assets: <String>['assets/tutorial/focus/working.png'],
    ),
    TutorialImageStep(
      body: <String>[
        '到休息时间时，Elychron会发通知告诉你。',
        '同时，你也可以随时选择暂停。',
      ],
      assets: <String>['assets/tutorial/focus/paused-effect.png'],
    ),
    TutorialImageStep(
      body: <String>[
        '这个时候就可以切换到Elychron的其他页面啦，临时想到什么待办非常实用！',
        '当然，再次回来后，可以继续刚刚暂停的专注。',
      ],
      assets: <String>['assets/tutorial/focus/paused-card.png'],
    ),
    TutorialTextStep(
      title: '专注记录',
      body: [
        '打开专注记录，可以看到历史上所有的专注时长。',
        '可以按照标签、待办、星期分类，统计起来非常方便。',
      ],
    ),
    TutorialTextStep(
      title: '你专注了吗？',
      body: ['rt，好好利用专注模式吧！'],
    ),
  ],
);
