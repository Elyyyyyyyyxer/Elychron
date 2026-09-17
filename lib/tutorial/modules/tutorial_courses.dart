import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程内容：课程相关 ============
///
/// **内容来源**：用户手写的 `docs/GUIDE_V1.4.1.md`「二、课程相关」一节。
/// 图是在真机的课程详情页拍的（`assets/tutorial/course/detail.png`），
/// 只截了稿子里点名的那三个功能区：资料 / 评论 / 相关待办。
const Tutorial tutorialCourses = Tutorial(
  id: 'courses',
  title: '课程：把资料、评论、待办挂上去',
  summary: '课程页能放课件与笔记、写点记录，还能把相关待办挂上来',
  // 归到「课表与日程」这一节：课程本来就住在课表里，从课表点进去最顺手
  group: TutorialGroup.calendar,
  steps: [
    TutorialTextStep(
      title: '课程页面能干什么',
      body: [
        '为了方便归类某些课程资料，Elychron 允许对课程页面添加文件、评论等。',
        '随手有想要记录的，比如课程评分、上课资料，都可以挂在上面。',
      ],
    ),
    TutorialTextStep(
      title: '怎么打开课程详情',
      body: [
        '在「日程 → 课表」里点任意一节课，或者从「学业 → 课程」里点一门课，都能进课程详情页。',
        '在原有的课程、上课时间、考试时间之外，Elychron 新增了三块：资料、评论、相关待办。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/course/detail.png',
      caption: '课程详情页：资料（课件/笔记/板书）· 评论 · 相关待办',
    ),
    TutorialTextStep(
      title: '资料与评论',
      body: [
        '「资料」里点「添加图片 / 文件」，可以把课件、笔记、板书照片放进这门课；',
        '「评论」适合写短记录 —— 课程评分、老师口头交代的事、下次要带什么，都可以随手记。',
      ],
    ),
    TutorialTextStep(
      title: '相关待办',
      body: [
        '「相关待办」把课程和待办连起来：这门课的作业、要交的材料都挂在这里，一目了然。',
        '点「新建待办并挂到这门课」可以直接建一条挂在这门课上的待办。',
        '挂上去之后，打开这门课就能看到还欠着什么，不用去待办列表里翻。',
      ],
    ),
  ],
);
