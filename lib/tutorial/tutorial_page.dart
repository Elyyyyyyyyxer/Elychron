import 'package:celechron/design/app_accent.dart';
import 'package:celechron/tutorial/steps/step_renderers.dart';
import 'package:celechron/tutorial/tutorial_model.dart';
import 'package:celechron/tutorial/tutorial_progress.dart';
import 'package:celechron/tutorial/tutorial_router.dart';
import 'package:celechron/tutorial/tutorial_store.dart';
import 'package:flutter/cupertino.dart';

/// ============ 教程播放器 ============
///
/// 一篇教程就是"一页一步"地看下去：
/// 顶部是标题 + 进度条，中间是这一步的内容，底部是「上一步 / 下一步」。
/// 最后一步的按钮是「看完了」；右上角菜单里有「不再提示」与「重新观看」。
///
/// 中途退出会**记住看到第几步**（下次接着看），但**不算看过** ——
/// "看过"只由最后一步的「看完了」标记，这样首用提示不会被半个教程糊弄过去。
class TutorialPage extends StatefulWidget {
  final Tutorial tutorial;

  /// 从某个功能的帮助按钮进来时，返回后可以给一句反馈
  final VoidCallback? onTargetOpened;

  const TutorialPage({super.key, required this.tutorial, this.onTargetOpened});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  late int _index;

  List<TutorialStep> get _steps => widget.tutorial.steps;
  int get _total => _steps.length;

  @override
  void initState() {
    super.initState();
    // 接着上次的位置看（没看过就是第 0 步）
    _index = TutorialStore.instance.lastIndex(widget.tutorial);
  }

  void _go(int index) {
    setState(() => _index = TutorialProgress.clamp(index, _total));
    TutorialStore.instance.saveProgress(widget.tutorial, _index);
  }

  Future<void> _finish() async {
    await TutorialStore.instance.markSeen(widget.tutorial);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _mute() async {
    await TutorialStore.instance.mute(widget.tutorial);
    if (mounted) Navigator.of(context).pop();
  }

  void _handleTarget(TutorialTarget target) {
    // 关掉教程，再由入口层统一跳转（跳转映射集中在 tutorial_entry.dart）
    Navigator.of(context).pop();
    widget.onTargetOpened?.call();
    openTutorialTarget(target);
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);
    final isLast = TutorialProgress.isLast(_index, _total);
    final isFirst = TutorialProgress.isFirst(_index);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          widget.tutorial.title,
          style: const TextStyle(fontSize: 17),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.ellipsis_circle, size: 22),
          onPressed: () => _showMore(context),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 进度条 + 第几步
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(
                            height: 6,
                            color: CupertinoDynamicColor.resolve(
                                CupertinoColors.systemFill, context),
                          ),
                          FractionallySizedBox(
                            widthFactor: TutorialProgress.ratio(_index, _total),
                            child: Container(height: 6, color: AppAccent.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_index + 1} / $_total',
                    style: TextStyle(fontSize: 12.5, color: labelColor),
                  ),
                ],
              ),
            ),
            Expanded(
              child: buildTutorialStep(
                context,
                _steps[_index],
                onTarget: _handleTarget,
              ),
            ),
            // 底部操作
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
              child: Row(
                children: [
                  if (!isFirst)
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.systemFill, context),
                        borderRadius: BorderRadius.circular(22),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        onPressed: () => _go(_index - 1),
                        child: const Text('上一步', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                  if (!isFirst) const SizedBox(width: 10),
                  Expanded(
                    flex: isFirst ? 1 : 1,
                    child: CupertinoButton(
                      color: AppAccent.primary,
                      borderRadius: BorderRadius.circular(22),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: isLast
                          ? _finish
                          : () => _go(TutorialProgress.nextIndex(_index, _total)),
                      child: Text(
                        isLast ? '看完了' : '下一步',
                        style: TextStyle(
                            color: AppAccent.onPrimary, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMore(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(context).pop();
              _go(0);
            },
            child: const Text('回到第一步'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(context).pop();
              _mute();
            },
            child: const Text('不再提示这篇'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }
}

/// 跳转目标的实际执行 —— 与 `TutorialTarget` 一一对应。
///
/// 真正的跳转由首页装进 [TutorialRouter]（见 `home_mod_hooks.dart`），
/// 这样教程内容与页面层保持解耦。
void openTutorialTarget(TutorialTarget target) {
  TutorialRouter.instance.open(target);
}
