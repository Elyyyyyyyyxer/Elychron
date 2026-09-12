# Elychron（Celechron 的非官方修改版）

> **Elychron 是 Celechron 的非官方修改版本（fork），不是官方发布。**
>
> - 上游项目：[Celechron/Celechron](https://github.com/Celechron/Celechron)（服务于浙大学生的时间管理器）
> - 本仓库：[Elyyyyyyyyxer/Elychron](https://github.com/Elyyyyyyyyxer/Elychron)
> - 基于上游版本：**v1.3.0**（commit `ceab2a4`），修改工作始于 2026 年 9 月
> - 许可协议：**GPLv3**（继承上游，见 [LICENSE](LICENSE)）。本仓库即为对应源码，
>   只要分发本程序的二进制，就有权获得这份源码。
> - 已改用独立 `applicationId`（`xyz.nosig.celechron.mod`），可与官方版本共存
>
> 与官方无关，遇到的问题请提到本仓库，不要去打扰上游作者。

## 魔改内容

### 待办（把原来的 DDL 与日程合并为统一的「待办」）

- 钉钉风格的**新建待办页**与**待办详情页**（完成待办 / 大标题 / 描述 / 截止时间+提醒 /
  优先级 / 子待办 / 附件 / 标签 / 地点 / 评论）
- 任务页顶部分类页签：**待我处理 / 优先处理 / 我已处理 / 星标**；
  第二行**分类（多选标签）/ 排序 / 筛选**，第三行为**标签管理 + 所有标签**
- **标签管理**：新建 / 删除 / 拖动排序 / 给标签配色（10 色盘）
- 子待办用**与新建待办相同的窗口**创建；有未完成子待办时完成主待办会二次确认
- 周期性待办完成之后自动生成下一次
- 待办详情右上角 ⋯ 菜单为钉钉风格（星标 / 删除待办）

### 提醒与闹钟

- 提醒方式可选**通知**（横幅弹出 + 响铃，带「延迟提醒 / 划掉」按钮）或
  **闹钟**（全屏提醒 + 循环播放系统闹钟铃声 + 震动，可延迟 10 分钟或划掉）
- 闹钟配色四套预设：**天依蓝 `#66CCFF`** / 爱莉粉 / 清新绿 / 静谧紫，
  浅色 + 毛玻璃，可在设置里预览真实页面

### 数据与同步基础

- 待办的 **JSON 导出 / 导入**（可存到坚果云），按 uid + `updatedAt` + 删除墓碑合并
- 删除待办会留**墓碑**，为多端同步做准备

### 其它

- 其它应用**分享**图片/文件/文字进来即可新建待办
- 日历显示待办并可直接打钩
- 全应用文案「任务」统一为「待办」

## 构建

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons
```

> ⚠️ Windows 上**项目路径不能含非 ASCII 字符**（Gradle 会直接拒绝），
> 中文目录下请用 junction / 软链映射到纯英文路径再构建。
> `--no-tree-shake-icons` 是为了绕开 Windows 应用控制策略对 `font-subset.exe` 的拦截。

## 许可

GPLv3。你可以自由使用、修改、再分发，但**必须**：
保留原版权与许可证声明、标注这是修改版、以同样的协议发布、并提供完整源码
（即本仓库）。不得附加"禁止商用/禁止转载"之类的额外限制。
详见 [LICENSE](LICENSE) 与 [MOD_NOTES.md](MOD_NOTES.md)、[docs/UPSTREAM.md](docs/UPSTREAM.md)。