/// ============ 钉钉风格的底部弹层（全 App 共用）============
///
/// 原来各处弹窗风格不统一：有的用 iOS 原生 `CupertinoActionSheet`（灰底 message
/// + 蓝字 action），有的用 `CupertinoAlertDialog`，还有自己画的。这里统一成一套：
///
/// - 圆角顶、跟随深浅色的底
/// - 大标题 + 可选说明
/// - 可选中列表（行：标题 + 副标题 + 粉色对勾）
/// - 底部整宽按钮：主操作粉色、取消灰色
///
/// 与 `tag_picker` / `system_alarm_picker` 的观感一致 —— 那两个已经是这个样式了，
/// 这里把它抽出来，让「默认提前量 / 专注时长 / 闹钟可靠性 / 导出课程表」也用同一套。
library;

import 'package:celechron/design/app_accent.dart';
import 'package:flutter/cupertino.dart';

/// 弹层里一个可选项
class DingTalkSheetOption<T> {
  final String label;
  final String? subtitle;

  /// 标签文字的颜色（例如优先级用各自的颜色）；不传就用默认文字色
  final Color? color;
  final T value;

  const DingTalkSheetOption({
    required this.label,
    required this.value,
    this.subtitle,
    this.color,
  });
}

/// 面板底部的一个次级按钮（灰底）
class DingTalkPanelAction {
  final String label;
  final VoidCallback onTap;

  const DingTalkPanelAction({required this.label, required this.onTap});
}

/// 弹层外壳：统一圆角、内边距、底部安全区
class DingTalkSheetShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const DingTalkSheetShell({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color ??
        CupertinoColors.label;
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);

    return Container(
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12.5, color: labelColor),
                    ),
                  ],
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 钉钉风格的选择弹层：给一组选项，返回选中的值（取消返回 null）。
///
/// [current] 传 null 表示**没有预选项**（适合"选择一个动作"这类弹层，
/// 比如「新建待办 / 添加到已有待办」）；传值时那一项右侧会打粉色对勾。
Future<T?> showDingTalkSheet<T>({
  required BuildContext context,
  required String title,
  required List<DingTalkSheetOption<T>> options,
  T? current,
  String? subtitle,
  String cancelLabel = '取消',
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (BuildContext context) => DingTalkSheetShell(
      title: title,
      subtitle: subtitle,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in options)
                  DingTalkSheetRow(
                    label: option.label,
                    subtitle: option.subtitle,
                    labelColorOverride: option.color,
                    selected: current != null && option.value == current,
                    onTap: () => Navigator.of(context).pop(option.value),
                  ),
              ],
            ),
          ),
        ),
        DingTalkSheetCancel(
          label: cancelLabel,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// 选择行：标题 + 副标题 + 选中时右侧粉色对勾
class DingTalkSheetRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool selected;

  /// 标签文字的覆盖色（例如优先级各自的颜色）
  final Color? labelColorOverride;
  final VoidCallback? onTap;

  const DingTalkSheetRow({
    super.key,
    required this.label,
    this.subtitle,
    this.selected = false,
    this.labelColorOverride,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color ??
        CupertinoColors.label;
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 0.5,
              color: CupertinoDynamicColor.resolve(
                  CupertinoColors.separator, context),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      color: labelColorOverride ?? textColor,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12.5, color: labelColor),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Icon(CupertinoIcons.check_mark,
                  size: 18, color: AppAccent.primary),
          ],
        ),
      ),
    );
  }
}

/// 底部整宽主按钮（粉色）
class DingTalkSheetPrimary extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const DingTalkSheetPrimary({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          color: AppAccent.primary,
          borderRadius: BorderRadius.circular(22),
          padding: const EdgeInsets.symmetric(vertical: 12),
          onPressed: onTap,
          child: Text(
            label,
            style: TextStyle(color: AppAccent.onPrimary, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

/// 底部整宽次级按钮（灰底）
class DingTalkSheetSecondary extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const DingTalkSheetSecondary({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color ??
        CupertinoColors.label;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemFill, context),
          borderRadius: BorderRadius.circular(22),
          padding: const EdgeInsets.symmetric(vertical: 12),
          onPressed: onTap,
          child: Text(label, style: TextStyle(fontSize: 16, color: textColor)),
        ),
      ),
    );
  }
}

/// 底部的「取消」（实为次级按钮，语义上关闭弹层）
class DingTalkSheetCancel extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const DingTalkSheetCancel({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) =>
      DingTalkSheetSecondary(label: label, onTap: onTap);
}

/// 面板里的一行「标签 —— 值」，可选状态图标（✅ / ⚠️）
class DingTalkInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool? ok;
  final IconData? icon;

  const DingTalkInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.ok,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color ??
        CupertinoColors.label;
    final statusColor = ok == null
        ? labelColor
        : (ok! ? CupertinoColors.systemGreen : CupertinoColors.systemOrange);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: labelColor),
            const SizedBox(width: 8),
          ],
          if (ok != null) ...[
            Icon(
              ok!
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.exclamationmark_circle,
              size: 16,
              color: statusColor,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14.5, color: textColor),
            ),
          ),
          Text(value, style: TextStyle(fontSize: 13.5, color: statusColor)),
        ],
      ),
    );
  }
}

/// 面板里的一段说明文字
class DingTalkPanelNote extends StatelessWidget {
  final String text;

  const DingTalkPanelNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, height: 1.4, color: labelColor),
      ),
    );
  }
}

/// 钉钉风格的「面板」：标题 + 任意内容 + 主按钮 + 若干次级按钮。
///
/// 用于闹钟可靠性这类"报告 + 跳转"的内容（不是单纯的选择列表）。
Future<void> showDingTalkPanel({
  required BuildContext context,
  required String title,
  required List<Widget> children,
  String? subtitle,
  String? primaryLabel,
  VoidCallback? onPrimary,
  List<DingTalkPanelAction> secondaryActions = const <DingTalkPanelAction>[],
}) {
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (BuildContext context) => DingTalkSheetShell(
      title: title,
      subtitle: subtitle,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
        if (secondaryActions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final action in secondaryActions)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                    color: CupertinoDynamicColor.resolve(
                        CupertinoColors.tertiarySystemFill, context),
                    borderRadius: BorderRadius.circular(18),
                    onPressed: action.onTap,
                    child: Text(action.label,
                        style: const TextStyle(fontSize: 14)),
                  ),
              ],
            ),
          ),
        if (primaryLabel != null)
          DingTalkSheetPrimary(label: primaryLabel, onTap: onPrimary),
        DingTalkSheetCancel(
          label: '关闭',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}
