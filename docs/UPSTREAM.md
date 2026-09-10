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
| `lib/main.dart` | 上游接入刷新协调器；我们改成每天首次打开刷新 |
| `lib/page/calendar/calendar_view.dart` | 上游小改；我们加了待办卡片与打钩 |
| `lib/page/task/task_view.dart` | 上游少量适配；我们基本重写 |
| `pubspec.yaml` | 版本号 |

**目标：让这一层的改动"少、集中、有标记"**：

- 我们在上游文件里的改动应集中成块，前后加标记，便于 rebase 时定位：

  ```dart
  // ===== MOD BEGIN: <用途> =====
  ...
  // ===== MOD END =====
  ```

- 能通过「新增文件 + 一处挂载」实现的功能，一律走这条路（魔改的闹钟、分享、同步都是这么做的）。
- 体积大的重写（`task_view.dart` 等）后续可考虑迁到 `lib/mod/` 下，上游文件只留薄壳转发。

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
| `mod-1.2.0` | 基于 `5b688e0`（v1.2.0） | 当前基线 |
| `v1.3.0` 影子合并实测 | `ceab2a4` | **17 处冲突 / 7 个文件**：`task_controller` 8 处、`option_controller` 3 处、`home_page` 2 处、`main`/`calendar_view`/`task_view`/`pubspec` 各 1 处；`database_helper`、`option_view` 自动合并成功，其余 68 个上游文件零冲突 |

## 五、分发合规备忘（GPLv3）

本项目继承上游的 **GPLv3**，因此：

- 分发二进制时**必须提供完整对应源码**（本仓库公开即可满足）
- 修改版必须保留原版权与许可证声明（`LICENSE` + app 内「关于」页的 GPL 声明），并标注"已修改"及日期
- **不得附加额外限制**（禁止商用/禁止二转/需授权等均不允许）
- 商标不在 GPL 授权范围内：**不要**使用官方名称与图标、不要使用浙大校徽等标识
- 已改用独立 `applicationId`（`xyz.nosig.celechron.mod`），与官方版本可共存
- 涉及用户数据的新功能（如接入云端 AI）必须默认关闭并明确告知
