# 上游跟版流程（Upstream Merge Playbook）

本项目是 [Celechron](https://github.com/Celechron/Celechron) 的**非官方修改版**，基于 `v1.2.0`
（commit `5b688e0`），遵循 GPLv3。上游在活跃更新，本文记录**如何低成本地把上游更新吸收进来**。

## 一、三层架构：为什么跟版成本可控

实测（`v1.2.0 → v1.3.0`）：上游改动 **76 个文件**，我们改动 **63 个文件**，**两边都改的只有 8 个**。

> 结论：上游维护的是"教务接入底座"，我们改的是"待办这一间房"。两者物理上几乎不重叠。

### 第一层：上游底座（**永远不改**）

```
lib/http/**                    教务/认证/爬虫（zjuam、zdbk、sztz、grs、ecard…）
lib/model/scholar.dart         数据模型
lib/model/semester.dart
lib/model/course.dart
lib/model/grade.dart
lib/model/exam.dart
lib/model/session.dart
lib/model/option.dart
lib/services/**                刷新协调、诊断日志、诊断报告
lib/worker/**                  后台任务
lib/page/scholar/**            成绩/课表/实践成绩 UI
```

**这一层直接跟随上游，零冲突。** 上游适配浙大接口变化的能力就是这样白拿的——
这也是本项目最不需要自己维护的部分。

### 第二层：魔改层（**我们的地盘**）

```
lib/model/task.dart            待办模型（含子待办/优先级/附件/评论/标签/星标/时间戳）
lib/model/tombstone.dart       删除墓碑
lib/design/**                  魔改新增的 UI 组件
lib/utils/**                   魔改新增的工具（分享/闹钟/数据同步…）
lib/page/task/task_create_page.dart
lib/page/task/task_alarm_page.dart
lib/database/**                适配器与数据库接入
test/**                        单元测试
```

都是新增文件，上游不碰 → 零冲突。

### 第三层：接缝点（**冲突只在这里，要主动压缩**）

| 文件 | 冲突原因 |
|---|---|
| `lib/page/task/task_controller.dart` | 上游做性能重构（`updateDeadlineList` 返回 `changed`、只在真变化时写库；定时器加 `onClose`）；我们加了墓碑、合并类型、重复生成 |
| `lib/page/option/option_controller.dart` | 上游后台刷新接入新协调器；我们移除了后台刷新、加了提醒方式设置 |
| `lib/page/home_page.dart` | 上游重构首页（`PageController` + `_KeepAlivePage`）；我们加了分享接收与闹钟监听 |
| `lib/main.dart` | 上游接入统一刷新入口 `_refreshRestoredScholar`（1.3 合并后已完全采用上游逻辑） |
| `lib/page/calendar/calendar_view.dart` | 上游小改；我们加了待办卡片与打钩 |
| `lib/page/task/task_view.dart` | 上游少量适配；我们基本重写 |
| `pubspec.yaml` | 版本号 |

> 1.3 合并时 `option_controller.dart` 也冲突过（上游强化了后台周期刷新）。当时的决策是
> 「继续移除后台刷新」，但随后**已按上游恢复**——理由见 `MOD_NOTES.md`：本魔改的初衷
> 是弥补 1.2 更新不及时，1.3 跟上之后就不需要这类权宜改动了。
> 现在 `main.dart` 与 `option_controller.dart` 都**完全等同上游**，冲突面比上表更小。

**目标：让这一层的改动"少、集中、有标记"**：

- 我们在上游文件里的改动应集中成块，前后加标记，便于 rebase 时定位：

  ```dart
  // ===== MOD BEGIN: <用途> =====
  ...
  // ===== MOD END =====
  ```

- 能通过「新增文件 + 一处挂载」实现的功能，一律走这条路（魔改的闹钟、分享、同步都是这么做的）。
- 体积大的重写（`task_view.dart` 等）后续可考虑迁到 `lib/mod/` 下，上游文件只留薄壳转发。

## 一点五、接缝压缩（进行中）

**原则：魔改逻辑一律放进 `lib/mod/`，上游文件里只留"调用点"。**

上游在持续重构（1.3 就把首页标签机制从 `CupertinoTabController` 换成了
`PageView` + `_KeepAlivePage`），所以凡是我们在上游文件里写的**逻辑**，
越少越好——冲突发生在重叠行上，逻辑挪走，冲突就只剩一行。

### 已完成

| 文件中转站 | 原接缝 | 现接缝 | 做法 |
|---|---|---|---|
| `lib/page/home_page.dart` | 102 行 | **16 行** | 分享接收 + 闹钟监听搬到 `lib/mod/home_mod_hooks.dart`，首页只留 `_modHooks.start()/dispose()` 与一行 import |
| `lib/page/task/task_controller.dart`（部分） | 285 行 | **212 行** | 前台闹钟检查、周期待办生成、旧数据归一化、删除墓碑、提醒同步搬到 `lib/mod/task_runtime_mod.dart`，每处只留一行调用 |

### 第 2 轮（已完成）

| 文件中转站 | 原接缝 | 现接缝 | 做法 |
|---|---|---|---|
| `task_controller.dart` | 212 行 | **36 行** | 分类/排序/筛选状态做成 `mixin TaskListFilterMod on GetxController`（`lib/mod/task_list_filter_mod.dart`），类声明只加一个 `with`。注意：**static 成员不会被 with 继承**，所以 `tabNames` 留在控制器里 |
| `option_view.dart` | 177 行 | **60 行** | 导出/导入的 110 行实现搬到 `lib/mod/settings_data_actions.dart`，顺带删掉 9 个只为它存在的 import |

三个文件的接缝合计：**564 行 → 112 行（−80%）**。

### 待办（按收益排序）

1. `option_view.dart` 剩余 60 行是两个声明式设置块（待办提醒方式 + 闹钟配色、数据分区），
   可做成 `lib/mod/settings_mod_section.dart` 的 widget，留 2 行挂载。
2. `lib/database/database_helper.dart`（114 行）：墓碑、标签库/配色、提醒方式、闹钟配色这些
   getter/setter 可以搬到 `extension DatabaseModExt on DatabaseHelper`
   （`optionsBox` / `tombstoneBox` 都是 public 字段），上游文件只留 4 行 adapter 注册 + 1 行开箱。
3. `lib/database/database_helper.dart`（114 行）：墓碑、标签库/配色、提醒方式、闹钟配色这些
   getter/setter 可以搬到 `extension DatabaseModExt on DatabaseHelper`
   （`optionsBox` / `tombstoneBox` 都是 public 字段），上游文件只留 4 行 adapter 注册 + 1 行开箱。
4. `lib/page/task/task_view.dart`（417 行）与 `task_edit_page.dart`（1205 行）是我们**整页重写**的。
   彻底的做法是把整页搬到 `lib/mod/`，上游文件保持原样（在我们这儿变成死代码），
   挂载点只留一行。**代价**：上游对这些页面的修复不再自动合并进来，将来要人工挑。
   当前它们没有产生过冲突（上游 1.3 没动这两个文件），所以**先不动**，列为观察项。

## 二、跟版步骤

```bash
# 1. 拿上游最新
git fetch upstream --tags

# 2. 在独立分支上合并（别直接在 main 上操作）
git checkout -b merge-upstream-1.4 main
git merge upstream/<tag>            # 或 rebase，视冲突情况而定

# 3. 解决冲突：只会在第三层出现，按 MOD 标记定位

# 4. 回归（必做）
flutter analyze                     # 期望 0 error
flutter test                        # 期望全部通过（当前 26 个用例）
# 真机走一遍：分享进来新建、闹钟响铃+延迟+划掉、导出/导入、卡片打钩、日历打钩、子待办完成校验

# 5. 合并回 main 并打 tag
git checkout main && git merge merge-upstream-1.4
git tag mod-1.4.0
git push origin main mod-1.4.0
```

## 三、分级跟版原则

| 上游改动类型 | 是否跟 | 说明 |
|---|---|---|
| 网络/认证/教务接口 | **必跟，越早越好** | 不跟可能哪天就登不上教务系统 |
| 性能/稳定性修复 | **建议跟** | 例如 1.3 的写库优化（不再每秒全量写 Hive） |
| 新功能（实践成绩、诊断日志等） | 可选 | 想要就挑，不想要就跳过 |
| 纯 UI 重构 | 可选 | 我们已重写的页面不必跟 |

## 四、基线记录

| 版本 | 上游 commit | 结果 |
|---|---|---|
| `mod-1.2.0` | 基于 `5b688e0`（v1.2.0） | 上一个基线 |
| `mod-1.3.0` | 合并 `ceab2a4`（v1.3.0） | **已完成**：17 处冲突 / 7 个文件（`task_controller` 8、`option_controller` 3、`home_page` 2、`main`/`calendar_view`/`task_view`/`pubspec` 各 1），`database_helper`、`option_view` 自动合并，其余 68 个上游文件零冲突。合并后 analyze 0 error、**132 个测试全绿**（上游自带 106 个成为额外回归网）、APK 构建通过。**实测工时约 1 小时**，与静态评估吻合 |

### 1.3 合并的解法（下次可参考）

| 冲突 | 决策 |
|---|---|
| `task_controller.dart`（8 处） | **吸收上游的 `changed` 门控重构**（不再每秒全量写 Hive），同时保留墓碑 / 旧数据归一化 / 周期待办生成 / 前台闹钟检查 |
| `home_page.dart`（2 处） | **采用上游的 `PageView` + `_KeepAlivePage`**，把分享与闹钟监听重新挂回，底栏保留「待办」 |
| `option_controller.dart`（3 处） | 先按原计划移除后台刷新，**后按上游恢复**（见上方说明） |
| `main.dart`（1 处） | 保留上游统一刷新入口，外层套我们的「每天首次刷新」→ **后按上游恢复** |
| `calendar_view.dart` / `task_view.dart` | 保留魔改（日历待办卡片、无进度条卡片），上游改的是同一处旧版本 |
| `pubspec.yaml` | 版本取 `1.3.0-mod.N+1` |

## 五、分发合规备忘（GPLv3）

本项目继承上游的 **GPLv3**，因此：

- 分发二进制时**必须提供完整对应源码**（本仓库公开即可满足）
- 修改版必须保留原版权与许可证声明（`LICENSE` + app 内「关于」页的 GPL 声明），并标注"已修改"及日期
- **不得附加额外限制**（禁止商用/禁止二转/需授权等均不允许）
- 商标不在 GPL 授权范围内：**不要**使用官方名称与图标、不要使用浙大校徽等标识
- 已改用独立 `applicationId`（`xyz.nosig.celechron.mod`），与官方版本可共存
- 涉及用户数据的新功能（如接入云端 AI）必须默认关闭并明确告知
