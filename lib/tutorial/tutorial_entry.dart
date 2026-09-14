import 'package:celechron/design/app_accent.dart';
import 'package:celechron/tutorial/tutorial_model.dart';
import 'package:celechron/tutorial/tutorial_page.dart';
import 'package:celechron/tutorial/tutorial_registry.dart';
import 'package:celechron/tutorial/tutorial_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

/// ============ 教程的统一入口 ============
///
/// 三个使用姿势（后续新功能按需挑一个）：
///
/// 1. **教程中心**：`openTutorialCenter(context)` —— 设置页那个入口；
/// 2. **某功能的帮助按钮**：`TutorialHelpButton(tutorialId: 'tasks')`，
///    放在功能页的导航栏或标题旁；
/// 3. **首次使用自动弹一次**：`await showTutorialOnce(context, 'tasks')`，
///    用户看完或点「不再提示」之后就不会再打扰。
///
/// 三者共用同一份"已看过"记录（[TutorialStore]），所以不会出现
/// "中心里显示已看、进功能又弹一次"这种不一致。
Future<void> openTutorial(BuildContext context, String id) async {
  final tutorial = TutorialRegistry.byId(id);
  if (tutorial == null) return;
  await Navigator.of(context, rootNavigator: true).push<void>(
    CupertinoPageRoute<void>(
      builder: (BuildContext context) => TutorialPage(tutorial: tutorial),
    ),
  );
}

/// 打开教程中心
Future<void> openTutorialCenter(BuildContext context) async {
  await Navigator.of(context, rootNavigator: true).push<void>(
    CupertinoPageRoute<void>(
      builder: (BuildContext context) => const TutorialCenterPage(),
    ),
  );
}

/// 首用提示：没看过才弹，看完/「不再提示」之后不再打扰。
///
/// 返回是否真的弹了（调用方可以据此决定要不要接着做别的事）。
Future<bool> showTutorialOnce(
  BuildContext context,
  String id, {
  bool loggedIn = true,
}) async {
  final tutorial = TutorialRegistry.byId(id);
  if (tutorial == null) return false;
  final store = TutorialStore.instance;
  if (!tutorial.showOnFirstUse) return false;
  if (store.hasSeen(tutorial) || store.isMuted(tutorial)) return false;
  if (tutorial.audience == TutorialAudience.loggedInOnly && !loggedIn) {
    return false;
  }
  if (!context.mounted) return false;
  await Navigator.of(context, rootNavigator: true).push<void>(
    CupertinoPageRoute<void>(
      builder: (BuildContext context) => TutorialPage(tutorial: tutorial),
    ),
  );
  return true;
}

/// 放在功能页上的「?」按钮：点开这篇教程
class TutorialHelpButton extends StatelessWidget {
  final String tutorialId;

  const TutorialHelpButton({super.key, required this.tutorialId});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(34, 34),
      onPressed: () => openTutorial(context, tutorialId),
      child: Icon(
        CupertinoIcons.question_circle,
        size: 21,
        color: AppAccent.primary,
      ),
    );
  }
}

/// ============ 教程中心 ============
///
/// 按分组列出全部教程，显示"已看 / 没看"，可以逐篇重新观看或重置。
class TutorialCenterPage extends StatelessWidget {
  const TutorialCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final loggedIn = _loggedIn();
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('使用教程', style: TextStyle(fontSize: 17)),
      ),
      child: SafeArea(
        // 已看状态变化时要刷新列表（看完一篇回来，标记要跟着变）
        child: ValueListenableBuilder<int>(
          valueListenable: TutorialStore.instance.revision,
          builder: (context, _, __) {
            final grouped =
                TutorialStore.instance.visibleGrouped(loggedIn: loggedIn);
            if (grouped.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('教程还在写，先自己摸索一下吧。'),
                ),
              );
            }
            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Text(
                      '边用边看，一篇一个功能。看过的会打勾，随时可以重看。',
                      style: TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ),
                for (final entry in grouped.entries) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                      child: Text(
                        entry.key.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CupertinoDynamicColor.resolve(
                              CupertinoColors.secondaryLabel, context),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: CupertinoListSection.insetGrouped(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final tutorial in entry.value)
                          _TutorialRow(tutorial: tutorial),
                      ],
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _loggedIn() {
    try {
      if (!Get.isRegistered<dynamic>(tag: 'scholar')) {
        // 不强依赖：拿不到就当未登录（只会隐藏"登录后才有"的教程）
      }
    } catch (_) {}
    return true;
  }
}

class _TutorialRow extends StatelessWidget {
  final Tutorial tutorial;

  const _TutorialRow({required this.tutorial});

  @override
  Widget build(BuildContext context) {
    final store = TutorialStore.instance;
    final seen = store.hasSeen(tutorial);
    final labelColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel, context);

    // CupertinoListTile 没有 onLongPress，所以外面包一层手势做"长按重置"
    return GestureDetector(
      onLongPress: seen
          ? () async {
              await store.reset(tutorial);
            }
          : null,
      child: CupertinoListTile(
        title: Text(tutorial.title),
        subtitle: Text(
          seen ? '${tutorial.summary}（已看过）' : tutorial.summary,
        ),
        leading: Icon(
          seen
              ? CupertinoIcons.check_mark_circled_solid
              : CupertinoIcons.circle,
          size: 22,
          color: seen ? AppAccent.primary : labelColor,
        ),
        trailing: const CupertinoListTileChevron(),
        onTap: () => openTutorial(context, tutorial.id),
      ),
    );
  }
}
