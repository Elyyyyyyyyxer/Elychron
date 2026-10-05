# 设置页重构方案（2026-09-30 起）

> 用户要求：「设置页面随着内容增多越来越复杂，请把它们分类折叠 —— 设置页面本身只是一个索引，
> 点击每个部分的卡片才会进入那个页面的全部设置项」，**双端都要**。

## 一、机制：给现有分区**加前缀**，不重写

设置页现在是 `option_view.dart` 里一个 `CustomScrollView`，slivers 依次是：

| 行 | 分区 | 现在是什么 |
|---|---|---|
| 75 | 教务（含 modReminderTiles：提醒方式/提前量/专注参数/休息提醒/免打扰/专注记录/DING） | Obx + CupertinoListSection |
| 270 | AI 智能助手 | `modAiSection(...)` |
| 273 | 数据（导出/导入/反馈/同步入口） | `modDataSection(...)` |
| 276 | 教程 | `modTutorialSection(...)` |
| 279 | 日程（含桌面端导出 iCal 分支） | Obx + CupertinoListSection |
| 367 | 工具（暗色模式/付款码…） | SliverToBoxAdapter |
| 402 | 诊断与测试（测试日志 + 应用错误） | SliverToBoxAdapter |
| 430 | 关于 | SliverToBoxAdapter |

**做法（低风险）**：给每一段 sliver 的**起始行加一个集合 if 前缀**：

```dart
// 日程
if (_show(SettingsCategory.courses)) Obx(() => SliverToBoxAdapter(...))
```

- 只需要知道每段的**起始**位置，**不需要**知道每段在哪里结束（不用去平衡括号）；
- 原代码一行都不改，只是"这段什么时候显示"变了；
- `OptionPage({this.category})`：`category == null` → 画**索引卡**（新页面）；
  指定类别 → 画**只属于那一类**的分区（复用现有 slivers）。

**调用点不用改**：手机底部标签与桌面导航现在都是 `OptionPage()` → 直接就是索引页 ✓

## 二、索引页（新文件 `lib/page/option/settings_index_page.dart`）

一张卡 = 一个分类（图标 + 名称 + 一句话 + 右侧箭头），点击 push `OptionPage(category: x)`。
双端同一份代码，只按 `PlatformFeatures.isDesktop` 调一下宽度上限（桌面上居中、最大宽度约 560，
不然一行拉太宽不好看）。

| 分类 | 名称 | 副标题 | 对应现有分区 |
|---|---|---|---|
| scholar | 教务与提醒 | 登录状态、绩点、推送、提醒方式与专注参数 | 行 75 那一段 |
| courses | 课表与日程 | 同步到系统日历、学期、iCal 导出导入 | 行 279 |
| ai | AI 智能助手 | 开关、Key、模型、调用记录 | 行 270 |
| data | 数据与同步 | 全平台同步、导出导入、反馈信息 | 行 273 |
| tools | 工具 | 暗色模式、付款码等 | 行 367 |
| tutorial | 使用教程 | 六篇教程 + 手把手引导 | 行 276 |
| diagnostics | 诊断与测试 | 测试日志、应用错误 | 行 402 |
| about | 关于 | 版本、服务条款、项目主页 | 行 430 |

## 三、要一起改的地方（别忘）

1. **教程高亮锚点**：`TutorialTarget.dataSection`（教程里"点这里打开设置→数据"）现在指向设置页的
   一个分区；重构后应该改成"打开「数据与同步」二级页"。**几篇教程的跳转要一起回归**。
2. **桌面端**：`desktop_frame.dart` 给设置页的宽度/边距约束，索引页要跟着看一遍。
3. **调试入口**：`--open-lan-page`、`--lan-selftest` 这些直开子页的路径不受影响（它们 push 的是别的页面）。

## 四、下一步（做完索引之后）

1. 把「专注参数 / 休息提醒 / 免打扰 / 专注记录」从第 1 类里**拆出来**，单独成「专注」类
   —— 需要把行 75 那个 `CupertinoListSection` 在 `// ===== MOD: 提醒方式 / 闹钟配色 =====` 处
   一分为二（各自带标题），这样分类才名副其实。
2. **设置项搜索**：分类做完之后上，能彻底解决"我明明记得有这个开关"。
