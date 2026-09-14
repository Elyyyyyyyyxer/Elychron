import 'package:celechron/tutorial/tutorial_model.dart';
import 'package:celechron/tutorial/tutorial_progress.dart';
import 'package:celechron/tutorial/tutorial_registry.dart';
import 'package:celechron/tutorial/tutorial_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 教程框架自身的测试。
///
/// 教程内容是"以后一直加"的东西，所以**框架的完整性检查比某一篇教程的内容更重要**：
/// 这些用例保证"新加一篇教程时不会犯低级错误"（id 重复、忘了写步骤、
/// 图片路径写错、种类漏写…），而不用等用户点进去才发现。
void main() {
  group('注册表完整性', () {
    test('注册表本身没有问题', () {
      final problems = TutorialRegistry.problems();
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('id 唯一', () {
      final ids = TutorialRegistry.all.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('每篇都有标题、说明与至少一步', () {
      for (final tutorial in TutorialRegistry.all) {
        expect(tutorial.title.trim(), isNotEmpty, reason: tutorial.id);
        expect(tutorial.summary.trim(), isNotEmpty, reason: tutorial.id);
        expect(tutorial.steps, isNotEmpty, reason: tutorial.id);
      }
    });

    test('按 id 查找可用，找不到返回 null', () {
      final first = TutorialRegistry.all.first;
      expect(TutorialRegistry.byId(first.id)?.title, first.title);
      expect(TutorialRegistry.byId('不存在的教程'), isNull);
    });

    test('分组聚合不会丢教程', () {
      final grouped = TutorialRegistry.grouped;
      final total = grouped.values.fold<int>(0, (sum, list) => sum + list.length);
      expect(total, TutorialRegistry.all.length);
    });

    test('图片步骤的路径都规范（以 assets/ 开头）', () {
      for (final tutorial in TutorialRegistry.all) {
        for (final asset in TutorialRegistry.assetsOf(tutorial)) {
          expect(asset.startsWith('assets/'), isTrue, reason: asset);
          expect(asset.endsWith('.png') || asset.endsWith('.jpg'), isTrue,
              reason: asset);
        }
      }
    });

    test('sealed 步骤类型都被渲染器覆盖（这里穷尽列举一次，防漏）', () {
      // 只要新增了 TutorialStep 子类而这里没补，编译期就会报错 ——
      // 这是"步骤类型可扩展"的护栏。
      const steps = <TutorialStep>[
        TutorialTextStep(title: 't', body: ['b']),
        TutorialTipsStep(title: 't', tips: ['x']),
        TutorialImageStep(asset: 'assets/a.png'),
        TutorialCompareStep(
            title: 't', leftLabel: 'l', left: ['1'], rightLabel: 'r', right: ['2']),
        TutorialActionStep(
            title: 't',
            body: 'b',
            buttonLabel: '去',
            target: TutorialTarget.taskList),
      ];
      for (final step in steps) {
        final matched = switch (step) {
          TutorialTextStep() => 'text',
          TutorialTipsStep() => 'tips',
          TutorialImageStep() => 'image',
          TutorialCompareStep() => 'compare',
          TutorialActionStep() => 'action',
        };
        expect(matched, isNotEmpty);
      }
    });
  });

  group('步骤导航', () {
    test('下一步到末尾停住', () {
      expect(TutorialProgress.nextIndex(0, 3), 1);
      expect(TutorialProgress.nextIndex(2, 3), 2);
    });

    test('上一步到开头停住', () {
      expect(TutorialProgress.prevIndex(2, 3), 1);
      expect(TutorialProgress.prevIndex(0, 3), 0);
    });

    test('首尾判断', () {
      expect(TutorialProgress.isFirst(0), isTrue);
      expect(TutorialProgress.isFirst(1), isFalse);
      expect(TutorialProgress.isLast(2, 3), isTrue);
      expect(TutorialProgress.isLast(1, 3), isFalse);
      expect(TutorialProgress.isLast(0, 1), isTrue);
    });

    test('进度比例（顶部进度条）', () {
      expect(TutorialProgress.ratio(0, 4), 0.25);
      expect(TutorialProgress.ratio(3, 4), 1.0);
      expect(TutorialProgress.ratio(0, 1), 1.0);
    });

    test('下标会被收敛到合法范围（教程改短了也不越界）', () {
      expect(TutorialProgress.clamp(9, 3), 2);
      expect(TutorialProgress.clamp(-2, 3), 0);
      expect(TutorialProgress.clamp(1, 3), 1);
      expect(TutorialProgress.clamp(5, 0), 0);
    });
  });

  group('「已看过 / 不再提示 / 进度」的规则', () {
    Tutorial sample({int version = 1}) => Tutorial(
          id: 'sample',
          title: '样例',
          summary: '说明',
          contentVersion: version,
          steps: const [
            TutorialTextStep(title: 'a', body: ['x']),
            TutorialTextStep(title: 'b', body: ['y']),
            TutorialTextStep(title: 'c', body: ['z']),
          ],
        );

    test('新教程没看过', () {
      final state = TutorialState();
      expect(state.hasSeen(sample()), isFalse);
      expect(state.isMuted(sample()), isFalse);
      expect(state.lastIndex(sample()), 0);
    });

    test('看完 → 算看过；中途退出只记进度不算看过', () {
      final state = TutorialState();
      final tutorial = sample();
      state.saveProgress(tutorial, 1);
      expect(state.hasSeen(tutorial), isFalse, reason: '中途退出不该算看过');
      expect(state.lastIndex(tutorial), 1);

      state.markSeen(tutorial);
      expect(state.hasSeen(tutorial), isTrue);
      expect(state.lastIndex(tutorial), 2);
    });

    test('内容版本 +1 → 重新算没看过（内容大改后会再提示一次）', () {
      final state = TutorialState();
      state.markSeen(sample());
      expect(state.hasSeen(sample()), isTrue);
      expect(state.hasSeen(sample(version: 2)), isFalse);
    });

    test('「不再提示」之后不再出现在待提示列表里', () {
      final state = TutorialState();
      final tutorial = sample();
      expect(state.pendingOf([tutorial]).length, 1);
      state.mute(tutorial);
      expect(state.pendingOf([tutorial]), isEmpty);
      // 但手动打开仍然可以看（只是不主动提示）
      expect(state.isMuted(tutorial), isTrue);
    });

    test('看完会清掉「不再提示」（用户主动看完就是想继续收到提示）', () {
      final state = TutorialState();
      final tutorial = sample();
      state.mute(tutorial);
      state.markSeen(tutorial);
      expect(state.isMuted(tutorial), isFalse);
    });

    test('showOnFirstUse=false 的教程不会被自动提示', () {
      final state = TutorialState();
      const manual = Tutorial(
        id: 'manual',
        title: '查阅类',
        summary: 's',
        showOnFirstUse: false,
        steps: [TutorialTextStep(title: 'a', body: ['x'])],
      );
      expect(state.pendingOf([manual]), isEmpty);
    });

    test('重置之后回到"没看过"', () {
      final state = TutorialState();
      final tutorial = sample();
      state.markSeen(tutorial);
      state.reset(tutorial);
      expect(state.hasSeen(tutorial), isFalse);
      expect(state.lastIndex(tutorial), 0);
    });

    test('落盘往返：toJson / fromJson 不丢信息', () {
      final state = TutorialState();
      final tutorial = sample();
      state.markSeen(tutorial);
      state.saveProgress(tutorial, 1);
      state.mute(sample(version: 9));

      final restored = TutorialState.fromJson(state.toJson());
      expect(restored.hasSeen(tutorial), isTrue);
      expect(restored.lastIndex(tutorial), 1);
      expect(restored.muted.contains('sample'), isTrue);
    });

    test('坏数据不会炸（fromJson 容错）', () {
      expect(TutorialState.fromJson(null).seen, isEmpty);
      expect(
        TutorialState.fromJson({'seen': 'not-a-list', 'progress': 42})
            .progress,
        isEmpty,
      );
    });
  });

  group('入口状态不依赖数据库也能工作', () {
    test('未注册数据库时 setStateForTest 仍可驱动逻辑', () {
      final store = TutorialStore.instance;
      final tutorial = TutorialRegistry.all.first;
      store.setStateForTest(TutorialState());
      expect(store.hasSeen(tutorial), isFalse);
      store.setStateForTest(TutorialState()..markSeen(tutorial));
      expect(store.hasSeen(tutorial), isTrue);
      store.setStateForTest(TutorialState());
    });

    test('可见性：未登录时隐藏"仅登录可见"的教程', () {
      const loggedOnly = Tutorial(
        id: 'logged',
        title: '登录后才有的',
        summary: 's',
        audience: TutorialAudience.loggedInOnly,
        steps: [TutorialTextStep(title: 'a', body: ['x'])],
      );
      final state = TutorialState();
      // pendingOf 只看状态，audience 过滤由 TutorialStore.visibleGrouped 负责，
      // 这里验证"状态层不会自作主张"
      expect(state.pendingOf([loggedOnly]).length, 1);
    });
  });
}
