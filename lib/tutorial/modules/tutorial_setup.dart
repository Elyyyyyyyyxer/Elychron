import 'package:celechron/tutorial/tutorial_model.dart';

/// ============ 教程内容：配置相关 ============
///
/// **内容全部来自用户手写的 `docs/GUIDE_V1.4.1.md`「零、配置相关」一节。**
///
/// ⚠️ 规矩（2026-09-17 用户明确要求）：**不要改用户的文案**。
/// 这里除了"把段落摆到该在的步骤里"之外，一个字都没有替他写 ——
/// 标题用他加粗的那几个（**配置环境** / **DeepSeek密钥配置** / …），
/// 小标题为空的地方就是同一节的续页（渲染器会隐藏空标题）。
/// 图片顺序照他稿子里的【图片】位置摆。
const Tutorial tutorialSetup = Tutorial(
  id: 'setup',
  title: '配置相关',
  summary: '想要把Elychron变得更加顺手，使用前请注意更改几个设置',
  group: TutorialGroup.basics,
  steps: [
    TutorialTextStep(
      title: '配置环境',
      body: [
        '想要把Elychron变得更加顺手，使用前请注意更改几个设置。',
        '当然这些设置不是必须的，但是Elychron强烈建议跟着操作一遍！',
      ],
    ),
    TutorialImageStep(
      title: 'DeepSeek密钥配置',
      body: [
        '这是使用Elychron核心功能的必要条件。据传Tixer最喜欢的就是这个功能。',
        '蓝色大肥鱼的API key配置方法并不复杂，懂的可以跳过。',
        '第一步，访问DeepSeek官方网站，点击API开放平台。',
      ],
      assets: <String>['assets/tutorial/setup/deepseek-home.png'],
    ),
    TutorialImageStep(
      body: <String>[
        '在左侧工具栏点击API keys，随后点击页面右侧的黑色按键 创建API key',
      ],
      assets: <String>['assets/tutorial/setup/deepseek-apikey.png'],
    ),
    TutorialImageStep(
      body: <String>[
        '在弹窗内输入API key的名字（随意就好），点击创建。',
        '请仔细保存好这个key！复制后直接粘贴到Elychron的设置-AI智能助手页面的API key里面。',
        '注意，直接复制粘贴可能会不成功，建议先在便签之类的地方中转一次再粘贴。',
        '最后不要忘了给DeepSeek打钱',
      ],
      assets: <String>['assets/tutorial/setup/deepseek-pay.png'],
    ),
    TutorialImageStep(
      title: '闹钟相关设置',
      body: <String>[
        '由于Elychron不是系统应用，很多闹钟功能无法复现。',
        '但是为了尽可能保持稳定性，可以进入设置-闹钟可靠性选项，按说明操作。',
      ],
      assets: <String>['assets/tutorial/setup/alarm-reliability.png'],
    ),
    TutorialTextStep(
      title: '',
      body: ['不过很可惜，按照操作之后还是有很多功能会被拦截……'],
    ),
    TutorialImageStep(
      title: '其他优化',
      body: <String>[
        '首先非常建议开启异步刷新。这样做的意义是可以同时尝试连接多个相关网站，减少登录延迟',
      ],
      assets: <String>['assets/tutorial/setup/settings-async-refresh.png'],
    ),
    TutorialImageStep(
      body: <String>[
        '然后，如果有问题想要反馈，建议附上设置内复制反馈信息功能的反馈日志，便于定位问题所在',
      ],
      assets: <String>['assets/tutorial/setup/settings-data.png'],
    ),
    TutorialTextStep(
      title: '继续看教程吧',
      body: [
        '除了基础配置，Elychron强烈建议看的教程还有“基本操作”。',
        '其他教程看个人需求就可以啦，欢迎来到Elychron！',
      ],
    ),
  ],
);
