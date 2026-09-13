import 'package:celechron/worker/fuse.dart';
import 'package:flutter_test/flutter_test.dart';

/// 更新策略：**小版本只提醒一次，大版本强制更新**（用户定的判据）。
///
/// 这里锁的是纯逻辑，不需要网络也不需要 GetX。
void main() {
  const local = [1, 4, 0];

  test('版本号比较：逐段比，高的才算新', () {
    expect(Fuse.isNewer([1, 4, 1], local), isTrue);
    expect(Fuse.isNewer([1, 5, 0], local), isTrue);
    expect(Fuse.isNewer([2, 0, 0], local), isTrue);
    expect(Fuse.isNewer([1, 4, 0], local), isFalse);
    expect(Fuse.isNewer([1, 3, 9], local), isFalse);
    expect(Fuse.isNewer([0, 9, 9], local), isFalse);
  });

  test('build 号更高也算有新版本（同一版本号内测包）', () {
    expect(Fuse.isNewer([1, 4, 0], local, remoteBuild: 6, localBuild: 5), isTrue);
    expect(Fuse.isNewer([1, 4, 0], local, remoteBuild: 5, localBuild: 5), isFalse);
  });

  test('主版本号变大 → 强制更新', () {
    expect(Fuse.isMajorBump([2, 0, 0], local), isTrue);
    expect(Fuse.isMajorBump([3, 1, 2], local), isTrue);
  });

  test('小版本更新不算强制（1.4.0 → 1.5.0 只提醒）', () {
    expect(Fuse.isMajorBump([1, 5, 0], local), isFalse);
    expect(Fuse.isMajorBump([1, 4, 1], local), isFalse);
    expect(Fuse.isMajorBump([1, 4, 0], local), isFalse);
  });

  test('小版本：只提醒一次，同 tag 再检查就不再打扰', () {
    // 第一次：lastPromptedTag 还是空的 → 提醒
    expect(
      Fuse.shouldPrompt(
          hasNew: true, forced: false, tag: 'v1.5.0', lastPromptedTag: null),
      isTrue,
    );
    // 第二次：已经提醒过同一个 tag → 安静
    expect(
      Fuse.shouldPrompt(
          hasNew: true, forced: false, tag: 'v1.5.0', lastPromptedTag: 'v1.5.0'),
      isFalse,
    );
    // 出了更新的小版本 → 再提醒一次
    expect(
      Fuse.shouldPrompt(
          hasNew: true, forced: false, tag: 'v1.5.1', lastPromptedTag: 'v1.5.0'),
      isTrue,
    );
  });

  test('大版本：不看「提醒过没有」，每次启动都提醒', () {
    expect(
      Fuse.shouldPrompt(
          hasNew: true, forced: true, tag: 'v2.0.0', lastPromptedTag: 'v2.0.0'),
      isTrue,
    );
  });

  test('没有新版本就不打扰', () {
    expect(
      Fuse.shouldPrompt(
          hasNew: false, forced: false, tag: 'v1.4.0', lastPromptedTag: null),
      isFalse,
    );
  });

  test('解析 tag 里的版本号', () {
    expect(Fuse.parseTagVersion('v1.4.0-elychron.1'), [1, 4, 0]);
    expect(Fuse.parseTagVersion('1.4.0-elychron.1'), [1, 4, 0]);
    expect(Fuse.parseTagVersion('v2.0.0'), [2, 0, 0]);
    expect(Fuse.parseTagVersion('nightly'), isNull);
  });
}
