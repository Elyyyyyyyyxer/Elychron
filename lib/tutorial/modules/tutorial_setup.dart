import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程内容：配置相关 ============
///
/// **内容来源**：用户 2026-09-17 手写的 `docs/GUIDE_V1.4.1.md`「零、配置相关」一节，
/// 六张图也是用户给的（DeepSeek 官网三张 + Elychron 设置三张），
/// 已复制进 `assets/tutorial/setup/` 随包发布。
///
/// 我只做了两件事：把文字搬进教程的数据结构、把图片放好。
/// **文案尽量照原文**（用户要求"记录人工写入的教程"），只在需要交代"为什么"的地方补了一句。
///
/// 为什么把它排在教程中心最前面：它是"用之前先改几个设置"，
/// 没配 DeepSeek 密钥的话，AI 整理那套功能是关着的。
const Tutorial tutorialSetup = Tutorial(
  id: 'setup',
  title: '开始之前：几项配置',
  summary: 'DeepSeek 密钥、闹钟可靠性、异步刷新 —— 用之前先改这几个设置',
  group: TutorialGroup.basics,
  steps: [
    TutorialTextStep(
      title: '先花两分钟配置',
      body: [
        '这些设置不是必须的，但配好之后 Elychron 会顺手很多，强烈建议跟着走一遍。',
        '一共四件小事：DeepSeek 密钥、闹钟可靠性、异步刷新、反馈日志。',
      ],
    ),
    TutorialTextStep(
      title: '一、拿一个 DeepSeek 密钥',
      body: [
        '这是使用 Elychron 核心功能（AI 整理待办）的必要条件 —— 不配也能用其它功能。',
        '先访问 DeepSeek 官方网站，点右下角的「使用 API 开放平台」。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/setup/deepseek-home.png',
      caption: 'DeepSeek 官网首页 —— 点「使用 API 开放平台」',
    ),
    TutorialTextStep(
      title: '创建 API key',
      body: [
        '在左侧工具栏点「API keys」，再点页面右侧的「创建 API key」。',
        '在弹窗里给它起个名字（随意就好），点创建。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/setup/deepseek-apikey.png',
    ),
    TutorialTipsStep(
      title: '拿到 key 之后要注意的',
      warning: true,
      tips: [
        '请仔细保存好这个 key —— 它就等于你的额度。',
        '复制后粘贴到 Elychron「设置 → AI 智能助手」的 API key 里。',
        '直接复制粘贴可能会不成功：建议先在便签之类的地方中转一次再粘贴。',
        '最后别忘了给 DeepSeek 充点钱，否则调用会失败。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/setup/deepseek-pay.png',
      caption: '充值入口（按需充，几块钱能用很久）',
    ),
    TutorialTextStep(
      title: '二、闹钟相关设置',
      body: [
        'Elychron 不是系统应用，很多闹钟能力没法复现。',
        '为了尽可能稳定，进「设置 → 闹钟可靠性」，照着说明逐条操作。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/setup/alarm-reliability.png',
      caption: '设置 → 闹钟可靠性：三条都变成绿色才算配好',
    ),
    TutorialTipsStep(
      title: '配完也还是会被拦一部分',
      warning: true,
      tips: [
        '按上面的做之后，仍然会有一些机型把后台闹钟拦掉 —— 这是非系统应用的先天限制，不是 App 坏了。',
        '真遇到"必须叫醒你"的事，可以在待办详情页把它「设为系统闹钟」兜底。',
      ],
    ),
    TutorialTextStep(
      title: '三、建议开启异步刷新',
      body: [
        '开启后可以同时尝试连接多个相关网站，减少登录等待时间。',
        '在「设置」里找到「异步刷新」并打开。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/setup/settings-async-refresh.png',
      caption: '设置里打开「异步刷新」',
    ),
    TutorialTextStep(
      title: '四、出问题时带上反馈日志',
      body: [
        '遇到问题想反馈时，先用「设置 → 数据 → 复制反馈信息」。',
        '它会把机型、系统、版本和**已脱敏**的日志一起复制到剪贴板，直接粘到群里就行 —— 比截图有用得多。',
      ],
    ),
    TutorialImageStep(
      asset: 'assets/tutorial/setup/settings-data.png',
      caption: '设置 → 数据：复制反馈信息',
    ),
    TutorialActionStep(
      title: '去看看「基本操作」',
      body: '除了基础配置，最值得看的是「基本操作」那篇（手势、翻页、折叠）。其它教程按需看就行 —— 欢迎来到 Elychron！',
      buttonLabel: '打开待办页',
      target: TutorialTarget.taskList,
    ),
  ],
);
