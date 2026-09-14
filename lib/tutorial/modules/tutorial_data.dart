import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程内容：数据与备份 ============
///
/// 另一篇示例，主要用来演示 [TutorialCompareStep]（两栏对比）这种步骤类型 ——
/// 它适合讲"和官方版的区别""以前和现在的区别"。
///
/// 注意 [TutorialCompareStep] 只是形态，别拿它当宣传位：
/// 两栏要写**事实**（能验的差异），不要写评价。
const Tutorial tutorialData = Tutorial(
  id: 'data',
  title: '数据：搬家、备份与导入',
  summary: '换手机怎么把待办带过去；iCal 与 JSON 分别适合什么场景',
  group: TutorialGroup.data,
  steps: [
    TutorialTextStep(
      title: 'Elychron 的数据存在本机',
      body: [
        '待办、标签、专注记录都存在手机本地，不上传任何服务器。',
        '所以换手机、或者想留个底，都需要你自己导出一次。',
      ],
    ),
    TutorialTipsStep(
      title: '两个导出，用途不同',
      tips: [
        '导出数据（JSON）：Elychron 的完整备份，含待办、标签、专注记录与设置。',
        '导出为 iCal 文件：给别人或别的日历用的标准格式，只含时间与标题。',
        '要搬回 Elychron 就用 JSON；要导进系统日历/电脑日历就用 iCal。',
      ],
    ),
    TutorialTextStep(
      title: '导入是"合并"，不是覆盖',
      body: [
        '导入 JSON 时按 uid 与更新时间比对：新的生效，旧的不动，两边都有的取更新的那条。',
        '删掉的待办会留一条"墓碑"记录，这样多台设备之间不会出现"删了又回来"。',
      ],
    ),
    TutorialCompareStep(
      title: '两种导入格式',
      leftLabel: 'JSON（导出数据）',
      left: [
        '完整备份，能原样搬回去',
        '含标签、专注记录、设置',
        '只有 Elychron 认识',
      ],
      rightLabel: 'iCal（.ics）',
      right: [
        '标准日历格式，通用',
        '只含时间、标题、地点、描述',
        '重复导入同一个文件不会重复',
      ],
    ),
    TutorialActionStep(
      title: '先导出一份放着',
      body: '建议现在就去导出一次 JSON 存到网盘 —— 换手机、刷机、误删都能救回来。',
      buttonLabel: '打开数据设置',
      target: TutorialTarget.dataSection,
    ),
  ],
);
