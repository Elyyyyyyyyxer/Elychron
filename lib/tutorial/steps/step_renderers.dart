import 'package:celechron/design/app_accent.dart';
import 'package:celechron/tutorial/tutorial_model.dart';
import 'package:flutter/cupertino.dart';

/// ============ 步骤渲染器 ============
///
/// 所有"长什么样"的决定都在这个文件里 —— 教程内容文件只写数据。
/// 想统一调整教程的观感（字号、间距、配色），改这里就够了。
///
/// ⚠️ **新增一种步骤类型时**：在 `tutorial_model.dart` 加子类，
/// 然后在下面的 [buildTutorialStep] 里补一个 case。
/// 这个 switch 是对 `sealed class TutorialStep` 的穷尽匹配，
/// **漏了会编译报错**（这正是选 sealed 的意义）。
Widget buildTutorialStep(
  BuildContext context,
  TutorialStep step, {
  required void Function(TutorialTarget target) onTarget,
}) {
  switch (step) {
    case TutorialTextStep(:final title, :final body):
      return _StepFrame(
        title: title,
        children: [
          for (final paragraph in body)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                paragraph,
                style: const TextStyle(fontSize: 15, height: 1.6),
              ),
            ),
        ],
      );
    case TutorialTipsStep(:final title, :final tips, :final warning):
      return _StepFrame(
        title: title,
        children: [
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    warning
                        ? CupertinoIcons.exclamationmark_triangle_fill
                        : CupertinoIcons.check_mark_circled_solid,
                    size: 17,
                    color: warning
                        ? CupertinoColors.systemOrange
                        : AppAccent.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(fontSize: 14.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    case TutorialImageStep(:final asset, :final caption):
      return _StepFrame(
        title: '',
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              // 图片还没准备好时给一个"占位说明"，而不是红叉 ——
              // 框架先搭、内容后补的阶段全靠它撑着
              errorBuilder: (context, error, stackTrace) =>
                  _MissingImage(asset: asset),
            ),
          ),
          if (caption != null && caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context),
                ),
              ),
            ),
        ],
      );
    case TutorialCompareStep(
        :final title,
        :final leftLabel,
        :final left,
        :final rightLabel,
        :final right
      ):
      return _StepFrame(
        title: title,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CompareColumn(
                  label: leftLabel,
                  items: left,
                  highlight: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompareColumn(
                  label: rightLabel,
                  items: right,
                  highlight: true,
                ),
              ),
            ],
          ),
        ],
      );
    case TutorialActionStep(
        :final title,
        :final body,
        :final buttonLabel,
        :final target
      ):
      return _StepFrame(
        title: title,
        children: [
          Text(body, style: const TextStyle(fontSize: 15, height: 1.6)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              color: AppAccent.primary,
              borderRadius: BorderRadius.circular(22),
              padding: const EdgeInsets.symmetric(vertical: 12),
              onPressed: () => onTarget(target),
              child: Text(
                buttonLabel,
                style: TextStyle(color: AppAccent.onPrimary, fontSize: 16),
              ),
            ),
          ),
        ],
      );
  }
}

/// 每一步的外壳：统一的标题与内边距
class _StepFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _StepFrame({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// 对比步的一栏
class _CompareColumn extends StatelessWidget {
  final String label;
  final List<String> items;
  final bool highlight;

  const _CompareColumn({
    required this.label,
    required this.items,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    return Container(
      decoration: BoxDecoration(
        color: highlight
            ? AppAccent.soft(0.12)
            : CupertinoDynamicColor.resolve(
                CupertinoColors.tertiarySystemFill, context),
        borderRadius: BorderRadius.circular(12),
        border: highlight
            ? Border.all(color: AppAccent.soft(0.5), width: 1)
            : null,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: highlight ? AppAccent.primaryText : labelColor,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(item, style: const TextStyle(fontSize: 13.5, height: 1.4)),
            ),
        ],
      ),
    );
  }
}

/// 图片缺失时的占位（内容后补阶段非常常见，所以做得明确一点）
class _MissingImage extends StatelessWidget {
  final String asset;

  const _MissingImage({required this.asset});

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.tertiarySystemFill, context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(CupertinoIcons.photo, size: 28, color: labelColor),
          const SizedBox(height: 10),
          Text(
            '这张图还没放进来',
            style: TextStyle(fontSize: 14, color: labelColor),
          ),
          const SizedBox(height: 6),
          Text(
            asset,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: labelColor),
          ),
        ],
      ),
    );
  }
}
