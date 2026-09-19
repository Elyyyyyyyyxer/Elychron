import 'package:celechron/model/focus_session.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// 专注记录的同步口径（v1.5.0，用户要求"加上设备名标注然后直接同步"）。
///
/// 这里锁两件事：
/// 1. **两台设备的记录并存**（各自按 uid 认领，互不覆盖）——
///    否则"手机专注 1 小时 + 电脑专注 2 小时"同步完只剩一边；
/// 2. **删掉的记录不再被带回来** —— 这是原来的已知局限（删除不参与同步），
///    用户这次提设备标注时一起要求修掉。
void main() {
  FocusSession make(String uid,
      {Duration focused = const Duration(minutes: 30)}) {
    final session = FocusSession(
      startedAt: DateTime(2026, 9, 19, 9, 0),
      endedAt: DateTime(2026, 9, 19, 9, 30),
      focusedTime: focused,
      completed: true,
    );
    session.uid = uid;
    return session;
  }

  test('两台设备的记录并存（按 uid 认领，不互相覆盖）', () {
    final merged = DataMerge.mergeFocusSessions(
      local: <FocusSession>[make('phone-1')],
      remote: <FocusSession>[make('pc-1'), make('pc-2')],
    );
    expect(
        merged.map((s) => s.uid).toSet(), <String>{'phone-1', 'pc-1', 'pc-2'});
  });

  test('本机删掉的记录不会被对方带回来', () {
    final merged = DataMerge.mergeFocusSessions(
      local: <FocusSession>[],
      remote: <FocusSession>[make('gone'), make('keep')],
      deletedUids: <String>{'gone'},
    );
    expect(merged.map((s) => s.uid).toList(), <String>['keep']);
  });

  test('删掉的判断是双向的：对方删了也一样', () {
    final merged = DataMerge.mergeFocusSessions(
      local: <FocusSession>[make('gone'), make('mine')],
      remote: <FocusSession>[make('gone')],
      deletedUids: <String>{'gone'},
    );
    // 本机这条也没了（删除优先于"本端在跑"那套规则）
    expect(merged.map((s) => s.uid).toList(), <String>['mine']);
  });

  test('同一条两边都有：本端还在跑就以本端为准', () {
    final running = FocusSession(
      startedAt: DateTime(2026, 9, 19, 10, 0),
      focusedTime: const Duration(minutes: 5),
    )..uid = 'same';
    final finished = make('same', focused: const Duration(minutes: 90));
    final merged = DataMerge.mergeFocusSessions(
      local: <FocusSession>[running],
      remote: <FocusSession>[finished],
    );
    expect(merged.single.focusedTime, const Duration(minutes: 5),
        reason: '会话归属设备才有发言权');
  });
}
