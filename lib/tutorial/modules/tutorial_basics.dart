import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程内容：基本操作 ============
///
/// **内容全部来自用户手写的 `docs/GUIDE_V1.4.1.md`一、基本操作一节**，
/// 一句话都没改。图片是我照他稿子里的【图片】（提示…）在真机上拍的：
/// ·尽量展示划到一半，露出两种颜色→ `input motionevent` 拖到一半按住不放再截
/// ·要求同时包含小圆和正在旋转的卡片→ 点下小圆的瞬间连拍抓帧
/// ·接下来页面的三条线 / 课表页面的横V字形图标→ 从整屏截图里裁出图标
///
/// ⚠️ 规矩：文案是用户的，**只做"把段落摆到该在的步骤里"这一件事**；
/// 同一节的后半页小标题留空（渲染器隐藏空标题）。
const Tutorial tutorialBasics = Tutorial(
  id: 'basics',
  title: '基本操作',
  summary: '许多操作不是通过文字引导的按键实现的，掌握这些手势能提升效率',
  group: TutorialGroup.basics,
  steps: [
    TutorialTextStep(
      title: '掌握基本操作',
      body: [
        '在使用 Elychron 的过程中，许多操作不是通过文字引导的按键实现的。掌握这些手势可以更方便地执行操作，熟练之后能够极大程度提升操作效率',
      ],
    ),
    TutorialTextStep(
      title: '待办的完成、删除与恢复',
      body: ['在待办页面，我们可以用三种手势对待办进行操作。'],
    ),
    TutorialImageStep(
      body: <String>['当待办未完成时右滑待办，可以直接完成'],
      assets: <String>['assets/tutorial/basics/swipe-done.png'],
    ),
    TutorialImageStep(
      body: <String>['左滑待办，可以直接删除'],
      assets: <String>['assets/tutorial/basics/swipe-delete.png'],
    ),
    TutorialImageStep(
      body: <String>['当待办已完成时右滑待办，可以恢复'],
      assets: <String>['assets/tutorial/basics/swipe-restore.png'],
    ),
    TutorialTextStep(
      title: '日历与接下来、课表的切换',
      body: ['在日程页面，我们可以切换三种显示方式，分别为日历，接下来，课表。'],
    ),
    TutorialImageStep(
      body: <String>['点击页面顶部中间的小圆，我们可以在接下来与日历/课表之间进行切换'],
      assets: <String>['assets/tutorial/basics/flip-card.png'],
    ),
    TutorialImageStep(
      body: <String>[
        '点击右上角的三条线，可以在课表与接下来/日历之间切换。再次点击可以切换回去',
      ],
      assets: <String>[
        'assets/tutorial/basics/icon-list.png',
        'assets/tutorial/basics/icon-schedule.png',
      ],
    ),
    TutorialTextStep(
      title: '日历的展开与收起',
      body: ['为了方便查看课表、聚焦有效信息，日历可以折叠。'],
    ),
    TutorialImageStep(
      body: <String>['点击（或滑动）横线图标，可以折叠日历'],
      assets: <String>['assets/tutorial/basics/fold-handle.png'],
    ),
    TutorialImageStep(
      body: <String>['折叠状态下点击V形图标，可以展开日历'],
      assets: <String>['assets/tutorial/basics/fold-chevron.png'],
    ),
    TutorialTextStep(
      title: '多页面平滑切换',
      body: [
        '当然了，通过左右滑动，我们可以快捷地在多个页面之间切换',
        '注意不要不小心完成某个待办哦！',
      ],
    ),
  ],
);
