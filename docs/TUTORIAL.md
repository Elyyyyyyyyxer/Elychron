# 教程模块：怎么加一篇教程

> 这份文档写给**以后加功能时的我们自己**。目标是：加一篇教程只需要**新建一个文件 +
> 注册表加一行**，不碰播放器、不碰样式、不改 `pubspec.yaml`。

---

## 一、目录结构

```
lib/tutorial/
├── tutorial_model.dart        数据模型：Tutorial / 步骤类型（sealed）/ 分组 / 目标
├── tutorial_registry.dart     注册表：全部教程在这里登记 + 完整性自查
├── tutorial_progress.dart     纯逻辑：步骤导航 + 「已看/静音/进度」状态（可单测）
├── tutorial_store.dart        持久化：状态读写 + 全局单例 + 可见性过滤
├── tutorial_page.dart         播放器：一页一步、进度条、上一步/下一步/看完了
├── tutorial_entry.dart        统一入口：教程中心 / ? 按钮 / 首用自动弹一次
├── steps/step_renderers.dart  各步骤类型的**渲染**（样式都在这里）
└── modules/                   各功能的教程**内容**（一篇一个文件）
    ├── tutorial_tasks.dart    （示例）待办
    └── tutorial_data.dart     （示例）数据与备份
```

**一条分界线**：`modules/` 里只有**数据**（标题、段落、图片路径…），
`steps/step_renderers.dart` 里只有**长什么样**。所以：
- 想统一调整教程观感（字号、间距、配色）→ 只改渲染器；
- 想加/改内容 → 只改 `modules/` 下的文件。

---

## 二、加一篇教程（三步）

### 第 1 步：新建内容文件

复制 `lib/tutorial/modules/tutorial_tasks.dart`，改名成 `tutorial_<功能>.dart`：

```dart
import 'package:celechron/tutorial/tutorial_model.dart';

const Tutorial tutorialFocus = Tutorial(
  id: 'focus',                     // 稳定标识；**改了它，用户的"已看过"记录会失效**
  title: '专注',
  summary: '一句话说明（教程中心列表里显示）',
  group: TutorialGroup.focus,      // 分类，决定它在教程中心的哪一节
  steps: [
    TutorialTextStep(title: '标题', body: ['第一段', '第二段']),
    TutorialTipsStep(title: '要点', tips: ['小技巧一', '小技巧二']),
    TutorialImageStep(asset: 'assets/tutorial/focus/main.png', caption: '说明'),
    TutorialActionStep(
      title: '去试试',
      body: '……',
      buttonLabel: '打开专注页',
      target: TutorialTarget.focus,
    ),
  ],
);
```

### 第 2 步：在注册表登记

`lib/tutorial/tutorial_registry.dart` 的 `_all` 里加一行：

```dart
static const List<Tutorial> _all = <Tutorial>[
  tutorialTasks,
  tutorialData,
  tutorialFocus,        // ← 加这里
];
```

### 第 3 步：放图片（可选）

图片放 `assets/tutorial/<教程id>/xxx.png`。

**不用改 `pubspec.yaml`** —— 它已经声明了整个 `assets/` 目录，新文件自动会被打包。
图还没准备好也没关系：播放器会显示一个占位框并写出期望路径，教程照样能走通。

> 跑一次 `flutter test test/tutorial_test.dart`：注册表自查会告诉你
> id 有没有重复、哪一步忘了写内容、图片路径是不是写错了。

---

## 三、步骤类型（5 种，可按需扩展）

| 类型 | 用途 | 关键字段 |
|---|---|---|
| `TutorialTextStep` | 讲清一件事 | `title`, `body`（段落列表） |
| `TutorialTipsStep` | 要点清单 / 注意事项 | `title`, `tips`, `warning`（橙色调） |
| `TutorialImageStep` | 截图或示意图 | `asset`, `caption` |
| `TutorialCompareStep` | 两栏对比（以前/现在、官方/改版） | `leftLabel/left`, `rightLabel/right` |
| `TutorialActionStep` | "现在去试试"+ 跳转按钮 | `buttonLabel`, `target` |

### 加一种新步骤类型（例如视频、折叠问答）

1. 在 `tutorial_model.dart` 里继承 `sealed class TutorialStep` 加子类；
2. 在 `steps/step_renderers.dart` 的 `switch` 里补一个 case；
3. 在 `tutorial_registry.dart` 的 `problems()` 里补一段字段校验（可选但推荐）。

**第 2 步漏了会编译报错** —— 这是特意用 `sealed` 的原因（穷尽性检查）。
`test/tutorial_test.dart` 里也有一处穷尽列举，双保险。

### 加一个跳转目标

1. `tutorial_model.dart` 的 `enum TutorialTarget` 加一个值；
2. 在 `tutorial_entry.dart`（或实际的跳转实现处）补上映射。

跳转目标用**枚举**而不是回调，是为了让内容文件保持"纯数据"。

---

## 四、三个使用姿势

### 1. 教程中心（已挂好）

设置 → 教程 → 使用教程。列表由注册表自动生成，按分组分节，
已看过的打勾，**长按可以重置**（重置后首用提示会再弹一次）。

### 2. 功能页上的「?」按钮

```dart
// 放在导航栏 trailing 或标题旁
TutorialHelpButton(tutorialId: 'focus')
```

### 3. 首次使用自动弹一次

```dart
// 进入某功能的页面时（记得 mounted 判断）
WidgetsBinding.instance.addPostFrameCallback((_) async {
  if (!mounted) return;
  await showTutorialOnce(context, 'focus');
});
```

三者**共用同一份"已看过"记录**，所以不会出现"教程中心显示已看过、进功能又弹一次"。

---

## 五、行为规则（已实现并有测试）

| 规则 | 说明 |
|---|---|
| **中途退出只记进度，不算看过** | 下次进来接着看；"看过"只由最后一步的「看完了」标记 |
| **内容版本 +1 → 重新算没看过** | 教程从 3 步扩到 10 步时，把 `contentVersion: 2`，老用户会再看一次 |
| **「不再提示」优先于自动弹** | 用户明确拒绝过就不再打扰；但手册式打开随时可以看 |
| **看完会清掉「不再提示」** | 主动看完 = 想继续收到提示 |
| **`showOnFirstUse: false`** | 纯查阅类教程（比如"常见问题"）不自动弹 |
| **教程改短了不会越界** | 进度下标会被收敛到合法范围 |
| **`loggedInOnly`** | 未登录时在教程中心隐藏（登录后才有的功能） |
| **坏数据不崩** | 状态从磁盘读回时全部用 `is` 判断，类型不对就当空（版本回退/手改过） |

---

## 六、写内容时的建议

- **一步只说一件事**：宁可多几步，也不要把手机屏塞满；
- **段落用列表给**：`body: ['第一段', '第二段']`，不要在一个字符串里换行；
- **先讲"这是什么/为什么"，再讲"怎么点"**：用户是遇到问题才来看的；
- **对比步只写事实**：能验证的差异（比如"只出 arm64"），不要写评价或宣传；
- **截图要露关键区域**，别整屏都贴 —— 手机上根本看不清；
- **文案就在内容文件里**（本仓库没有独立语言文件），想改文案直接改那个文件。

---

## 七、给后来者的两条提醒

1. **别把样式写进 `modules/`**：一旦某个模块自带 `TextStyle`，
   以后统一调整就得满目录找。渲染器才是唯一的样式出口。
2. **别删 `id`**：`id` 是"已看过"记录的键，改了等于让所有用户重看一遍。
   真要改就同时把 `contentVersion` +1（这是有意的重新提示），并接受多弹一次。
