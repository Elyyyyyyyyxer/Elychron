import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程内容：课程相关 ============
///
/// **内容全部来自用户手写的 `docs/GUIDE_V1.4.1.md`二、课程相关一节**，一句话都没改。
/// 图片按他稿子里的要求（"只需要显示我提到的三个功能"）拍：
/// 真机进课程详情页，裁到只剩 资料 / 评论 / 相关待办 那三块。
const Tutorial tutorialCourses = Tutorial(
  id: 'courses',
  title: '课程相关',
  summary: '给课程页面添加文件、评论，把相关待办也挂上去',
  group: TutorialGroup.calendar,
  steps: [
    TutorialTextStep(
      title: '课程页面',
      body: [
        '为了方便归类某些课程资料等，Elychron允许对课程页面添加文件、评论等。',
        '随手有想要记录的，比如课程评分，上课资料，都可以挂在上面',
      ],
    ),
    TutorialImageStep(
      title: '课程详情页',
      body: <String>[
        '在原有的课程、上课时间、考试时间之外，Elychron新增了资料、评论、相关待办等选项',
      ],
      assets: <String>['assets/tutorial/course/detail.png'],
    ),
  ],
);
