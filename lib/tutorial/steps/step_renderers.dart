import 'package:celechron/design/app_accent.dart';
import 'package:celechron/tutorial/tutorial_model.dart';
import 'package:flutter/cupertino.dart';

/// ============ 步骤渲染器 ============
///
/// 所有"长什么样"的决定都在这个文件里， 教程内容文件只写数据。
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
    case TutorialImageStep(
        :final assets,
        :final title,
        :final caption,
        :final body,
        :final warning
      ):
      return _StepFrame(
        title: title,
        children: [
          // 文字与图在**同一步**里（用户 2026-09-17 明确要求）
          for (final paragraph in body)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                paragraph,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: warning
                      ? CupertinoColors.systemOrange
                      : CupertinoColors.label,
                ),
              ),
            ),
          for (final asset in assets) ...[
            _TutorialImage(asset: asset),
            const SizedBox(height: 14),
          ],
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
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Container(
      decoration: BoxDecoration(
        color: highlight
            ? AppAccent.soft(0.12)
            : CupertinoDynamicColor.resolve(
                CupertinoColors.tertiarySystemFill, context),
        borderRadius: BorderRadius.circular(12),
        border:
            highlight ? Border.all(color: AppAccent.soft(0.5), width: 1) : null,
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
              child: Text(item,
                  style: const TextStyle(fontSize: 13.5, height: 1.4)),
            ),
        ],
      ),
    );
  }
}

/// 教程配图：等比缩放 + **限高** + **点开全屏放大**
///
/// 为什么要限高：手机截图是竖长条（1080×2376 这种），按宽度铺满会占掉两屏多，
/// 用户得一直往下拉才能看到下一步的按钮。这里给一个高度上限，
/// 想看清细节就**点图**，全屏、可捏合缩放，这也是教程里最常用的动作。
///
/// 右下角那个小角标不是装饰：没有它，用户不知道这张图可以点。
class _TutorialImage extends StatelessWidget {
  final String asset;

  const _TutorialImage({required this.asset});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.46;
    final fill = CupertinoDynamicColor.resolve(
        CupertinoColors.tertiarySystemFill, context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 点图放大这四个字**放在图片外面**（右上角）。
        // 第一版是压在图的右下角， 真机一看就发现问题：短图会被挡住正文那行字。
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.arrow_up_left_arrow_down_right,
                    size: 12, color: fill),
                const SizedBox(width: 4),
                Text('点图放大', style: TextStyle(fontSize: 11.5, color: fill)),
              ],
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              fullscreenDialog: true,
              builder: (context) => _TutorialImageFullScreen(asset: asset),
            ),
          ),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: maxHeight),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                // ⚠️ 这里用 Image(...) 而不是 Image.asset(...)：本仓库用的 Flutter
                // 版本里 Image.asset 那个命名构造函数**没有暴露 loadingBuilder**
                // （内部写死成 null），想要"解码时转圈"只能用默认构造函数。
                child: Image(
                  image: AssetImage(asset),
                  fit: BoxFit.contain,
                  // 解码要一点时间（截图几百 KB），给个转圈，别让用户以为没反应
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CupertinoActivityIndicator(radius: 12)),
                  // 图片还没准备好时给一个"占位说明"，而不是红叉，
                  // 框架先搭、内容后补的阶段全靠它撑着
                  errorBuilder: (context, error, stackTrace) =>
                      _MissingImage(asset: asset),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 全屏看图：捏合缩放 + 拖动，点完成返回
class _TutorialImageFullScreen extends StatelessWidget {
  final String asset;

  const _TutorialImageFullScreen({required this.asset});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black.withValues(alpha: 0.85),
        border: null,
        // ⚠️ 别写双击放大：InteractiveViewer **自带**的只有捏合缩放与拖动，
        // 双击缩放要自己接手势。写了做不到的话，用户会以为坏了。
        middle: const Text('捏合放大 · 拖动查看',
            style: TextStyle(fontSize: 13, color: CupertinoColors.white)),
        // 左上角给一个返回箭头：原来是 fullscreenDialog 自动生成的取消，
        // 而"看图"这件事没有"取消"可言，文案不对。
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          // 图标按钮要给语义标签，否则读屏用户只会听到"按钮"
          child: const Icon(CupertinoIcons.back,
              color: CupertinoColors.white, semanticLabel: '返回'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成',
              style: TextStyle(fontSize: 16, color: CupertinoColors.white)),
        ),
      ),
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 6,
        // 只有捏合与拖动（见上面 navigationBar 里的注释）
        child: Center(
          child: Image(
            image: AssetImage(asset),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Padding(
              padding: const EdgeInsets.all(24),
              child: _MissingImage(asset: asset),
            ),
          ),
        ),
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
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
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
