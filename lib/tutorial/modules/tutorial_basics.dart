import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程内容：基本操作 ============
///
/// **内容来源**：用户手写的 `docs/GUIDE_V1.4.1.md`「一、基本操作」一节。
/// 图片是我照稿子里的【图片】（提示…）在真机上截的——
/// 稿子里怎么写我就怎么拍（"划到一半、露出两种颜色"、"同时包含小圆和正在旋转的卡片"…）。
///
/// 截图规范（见 `assets/tutorial/README.txt`）：**不能出现任何个人数据** ——
/// 所以待办那几张用的是我自己建的「示例任务：××」，拍完就删；
/// 画面也裁到只剩要讲的那一块。
const Tutorial tutorialBasics = Tutorial(
  id: 'basics',
  title: '基本操作：手势与翻页',
  summary: '待办的三种滑动、日历与课表的切换、日历折叠、页面之间怎么滑',
  group: TutorialGroup.basics,
  steps: [
    TutorialTextStep(
      title: '很多操作靠手势',
      body: [
        '在使用 Elychron 的过程中，许多操作不是通过文字引导的按键实现的。',
        '掌握这些手势可以更方便地执行操作，熟练之后能极大程度提升效率。',
      ],
    ),
    TutorialTextStep(
      title: '一、待办的完成、删除与恢复',
      body: [
        '在待办页面，可以用三种手势对待办进行操作。',
        '下面三张图都是"划到一半"的样子 —— 露出底色就说明手势已经认到了，松手即生效。',
      ],
    ),
    TutorialTextStep(
      title: '未完成时右滑 → 完成',
      body: ['往右滑一条未完成的待办，松手就完成了。'],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/basics/swipe-done.png',
      caption: '右滑：露出绿色的「完成」',
    ),
    TutorialTextStep(
      title: '左滑 → 删除',
      body: ['往左滑，松手就删除（会进回收站，不会立刻消失得无影无踪）。'],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/basics/swipe-delete.png',
      caption: '左滑：露出红色的「删除」',
    ),
    TutorialTextStep(
      title: '已完成时右滑 → 恢复',
      body: [
        '在「我已处理」里，往右滑一条已完成的待办，可以把它恢复成未完成。',
        '（完成错了、或者事情又来了，都用这个。）',
      ],
    ),
    TutorialTextStep(
      title: '二、日历 / 接下来 / 课表，怎么切',
      body: [
        '日程页面有三种显示方式：日历、接下来、课表。',
        '点页面顶部中间的小圆，可以在「接下来」与「日历」之间翻转切换。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/basics/flip-card.png',
      caption: '顶部小圆 + 正在翻转的卡片（点一下就好）',
    ),
    TutorialTextStep(
      title: '右上角那个图标负责另一半',
      body: [
        '点右上角的图标，可以在「课表」与「接下来 / 日历」之间切换；再点一次就切回来。',
        '同一个位置，在「接下来 / 日历」里长这样：',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/basics/icon-list.png',
      caption: '接下来 / 日历页面：右上角的三条线 → 切到课表',
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/basics/icon-schedule.png',
      caption: '课表页面：右上角的横 V 图标 → 切回接下来 / 日历',
    ),
    TutorialTextStep(
      title: '三、日历可以折叠',
      body: [
        '为了方便查看课表、聚焦有效信息，日历可以折叠起来。',
        '点（或者滑）那根横线图标就能折叠日历；折叠状态下点 V 形图标可以再展开。',
      ],
    ),
    TutorialTextStep(
      title: '四、页面之间可以左右滑',
      body: [
        '通过左右滑动，可以在「日程 / 待办 / 专注 / 学业 / 设置」之间快速切换。',
        '⚠️ 小提醒：在待办列表里左右滑是"完成 / 删除"，所以滑的时候**别停在待办这一屏**，',
        '不然很容易不小心完成或删掉某条待办。',
      ],
    ),
  ],
);
