import 'dart:convert';

import 'package:celechron/model/focus_session.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// S1：多端同步契约与合并规则的测试。
///
/// 重点钉三件事：
/// 1. **老备份仍然能导入**（只加字段不改老字段）；
/// 2. **密钥白名单是机制**，不是约定 —— 非白名单的键（比如教务网密码）塞进去也进不来；
/// 3. 专注记录的合并规则（会话的删除暂不参与同步，已知局限）。
void main() {
  final t0 = DateTime(2026, 9, 12, 10, 0);

  Task makeTask({
    String uid = 't1',
    String summary = '写报告',
    DateTime? updatedAt,
  }) =>
      Task(
        uid: uid,
        summary: summary,
        endTime: DateTime(2026, 9, 20, 23, 59),
        startTime: DateTime(2026, 9, 20, 23, 59),
        repeatEndsTime: DateTime(2026, 9, 20),
        createdAt: t0,
        updatedAt: updatedAt ?? t0,
      );

  FocusSession makeSession({
    String uid = 's1',
    required DateTime startedAt,
    int focusedMinutes = 60,
    DateTime? endedAt,
  }) =>
      FocusSession(
        uid: uid,
        label: '敲代码',
        startedAt: startedAt,
        endedAt: endedAt ?? startedAt.add(Duration(minutes: focusedMinutes)),
        focusedTime: Duration(minutes: focusedMinutes),
      );

  group('契约：只加字段，老备份照样能导入', () {
    test('新字段能往返', () {
      final bundle = DataBundle(
        exportedAt: t0,
        deviceId: 'device-abc',
        tasks: [makeTask()],
        tombstones: const [],
        tags: ['作业'],
        tagColors: const {'作业': 3},
        reminderMode: 1,
        alarmTheme: 'elysia',
        focusSessions: [makeSession(startedAt: t0)],
        focusWorkMinutes: 45,
        focusRestMinutes: 10,
        focusRestNotify: false,
        reminderLeadMinutes: 15,
        brightnessMode: 2,
        courseIdMapping: [<String, dynamic>{'id1': 'A', 'id2': 'B', 'comment': '算法'}],
      );

      final back = DataBundle.decode(bundle.encode())!;
      expect(back.deviceId, 'device-abc');
      expect(back.tasks.single.summary, '写报告');
      expect(back.focusSessions.single.focusedTime, const Duration(minutes: 60));
      expect(back.focusWorkMinutes, 45);
      expect(back.focusRestMinutes, 10);
      expect(back.focusRestNotify, isFalse);
      expect(back.reminderLeadMinutes, 15);
      expect(back.brightnessMode, 2);
      expect(back.courseIdMapping.single['comment'], '算法');
      expect(back.tags, ['作业']);
      expect(back.tagColors['作业'], 3);
      expect(back.alarmTheme, 'elysia');
    });

    test('version 1 的老备份（没有新字段）仍然能导入，新字段取默认值', () {
      // 手工造一份「老版本」的包：只有原来的那些键
      final legacy = jsonEncode({
        'format': 'celechron-mod',
        'version': 1,
        'exportedAt': t0.toIso8601String(),
        'tasks': [
          {
            'uid': 'old-1',
            'summary': '老待办',
            'endTime': DateTime(2026, 9, 20, 23, 59).toIso8601String(),
            'startTime': DateTime(2026, 9, 20, 23, 59).toIso8601String(),
            'repeatEndsTime': DateTime(2026, 9, 20).toIso8601String(),
          }
        ],
        'tombstones': <Object>[],
        'tags': ['旧标签'],
        'tagColors': {'旧标签': 1},
        'settings': {'reminderMode': 1, 'alarmTheme': 'tianyi'},
      });

      final back = DataBundle.decode(legacy)!;
      expect(back.tasks.single.summary, '老待办');
      expect(back.deviceId, '');
      expect(back.focusSessions, isEmpty);
      // 默认值必须与设置里的默认一致
      expect(back.focusWorkMinutes, 60);
      expect(back.focusRestMinutes, 15);
      expect(back.focusRestNotify, isTrue);
      expect(back.reminderLeadMinutes, 30);
      expect(back.secrets, isEmpty);
    });

    test('不是本应用导出的文件 → null', () {
      expect(DataBundle.decode('{"format":"something-else"}'), isNull);
      expect(DataBundle.decode('not json'), isNull);
    });
  });

  group('密钥白名单（安全机制，不是约定）', () {
    test('白名单里的键能同步', () {
      final bundle = DataBundle(
        exportedAt: t0,
        tasks: const [],
        tombstones: const [],
        tags: const [],
        tagColors: const {},
        reminderMode: 0,
        alarmTheme: 'tianyi',
        secrets: const {
          SyncSecrets.aiApiKey: 'sk-test',
          SyncSecrets.amapKey: 'amap-test',
          SyncSecrets.webdavPassword: 'nutstore-pass',
        },
      );
      final back = DataBundle.decode(bundle.encode())!;
      expect(back.secrets[SyncSecrets.aiApiKey], 'sk-test');
      expect(back.secrets[SyncSecrets.amapKey], 'amap-test');
      expect(back.secrets[SyncSecrets.webdavPassword], 'nutstore-pass');
    });

    test('★ 非白名单的键（例如教务网密码）塞进去也进不来', () {
      // 模拟「有人把凭据写进了包」
      final raw = jsonEncode({
        'format': 'celechron-mod',
        'version': 2,
        'exportedAt': t0.toIso8601String(),
        'tasks': <Object>[],
        'tombstones': <Object>[],
        'tags': <Object>[],
        'tagColors': <String, int>{},
        'secrets': {
          'zju.password': '我的教务网密码',
          'zju.username': '3200000000',
          SyncSecrets.aiApiKey: 'sk-ok',
        },
        'settings': <String, Object>{},
      });
      final back = DataBundle.decode(raw)!;
      expect(back.secrets.containsKey('zju.password'), isFalse);
      expect(back.secrets.containsKey('zju.username'), isFalse);
      expect(back.secrets[SyncSecrets.aiApiKey], 'sk-ok');
    });

    test('空值不进包（省得把空字符串传来传去）', () {
      final bundle = DataBundle(
        exportedAt: t0,
        tasks: const [],
        tombstones: const [],
        tags: const [],
        tagColors: const {},
        reminderMode: 0,
        alarmTheme: 'tianyi',
        secrets: const {SyncSecrets.aiApiKey: ''},
      );
      expect(DataBundle.decode(bundle.encode())!.secrets, isEmpty);
    });
  });

  group('专注记录的合并', () {
    test('只在本端 / 只在对方：都保留（按 uid 去重）', () {
      final merged = DataMerge.mergeFocusSessions(
        local: [makeSession(uid: 'a', startedAt: t0)],
        remote: [makeSession(uid: 'b', startedAt: t0.add(const Duration(hours: 1)))],
      );
      expect(merged.map((s) => s.uid).toSet(), {'a', 'b'});
    });

    test('同 uid：结束得晚的那条赢', () {
      final local = makeSession(uid: 'a', startedAt: t0, focusedMinutes: 30);
      final remote = makeSession(uid: 'a', startedAt: t0, focusedMinutes: 60);
      final merged = DataMerge.mergeFocusSessions(local: [local], remote: [remote]);
      expect(merged.single.focusedTime, const Duration(minutes: 60));
    });

    test('本端还在跑（endedAt 为空）→ 以本端为准，别被对方的旧数据盖掉', () {
      final running = FocusSession(
        uid: 'a',
        label: '敲代码',
        startedAt: t0,
        endedAt: null,
        focusedTime: const Duration(minutes: 5),
      );
      final finished = makeSession(uid: 'a', startedAt: t0, focusedMinutes: 90);
      final merged = DataMerge.mergeFocusSessions(
        local: [running],
        remote: [finished],
      );
      expect(merged.single.isRunning, isTrue);
      expect(merged.single.focusedTime, const Duration(minutes: 5));
    });

    test('结果按开始时间倒序', () {
      final merged = DataMerge.mergeFocusSessions(
        local: [makeSession(uid: 'old', startedAt: t0)],
        remote: [
          makeSession(uid: 'new', startedAt: t0.add(const Duration(days: 1)))
        ],
      );
      expect(merged.first.uid, 'new');
    });
  });

  group('待办合并：墓碑优先 + 冲突如实汇报', () {
    test('两边都改过同一条 → 新的赢，并记进 conflictUids', () {
      // 本端确实改过：updatedAt 晚于 createdAt
      final local = makeTask(updatedAt: t0.add(const Duration(minutes: 1)));
      final remote = makeTask(
        summary: '远端改过的标题',
        updatedAt: t0.add(const Duration(minutes: 5)),
      );
      final result = DataMerge.merge(
        local: [local],
        localTombstones: const [],
        incoming: DataBundle(
          exportedAt: t0,
          tasks: [remote],
          tombstones: const [],
          tags: const [],
          tagColors: const {},
          reminderMode: 0,
          alarmTheme: 'tianyi',
        ),
      );
      expect(result.updated, 1);
      expect(result.tasks.single.summary, '远端改过的标题');
      expect(result.conflictUids, contains('t1'));
    });

    test('本端从没动过这条（updatedAt == createdAt）→ 不算冲突，别刷屏', () {
      final untouched = makeTask(); // createdAt == updatedAt
      final remote = makeTask(
        summary: '远端改的',
        updatedAt: t0.add(const Duration(minutes: 5)),
      );
      final result = DataMerge.merge(
        local: [untouched],
        localTombstones: const [],
        incoming: DataBundle(
          exportedAt: t0,
          tasks: [remote],
          tombstones: const [],
          tags: const [],
          tagColors: const {},
          reminderMode: 0,
          alarmTheme: 'tianyi',
        ),
      );
      expect(result.updated, 1);
      expect(result.conflictUids, isEmpty);
    });

    test('设置按「谁导出得更晚」取舍', () {
      final incoming = DataBundle(
        exportedAt: t0.add(const Duration(hours: 1)),
        tasks: const [],
        tombstones: const [],
        tags: const [],
        tagColors: const {},
        reminderMode: 1,
        alarmTheme: 'elysia',
      );
      final newer = DataMerge.merge(
        local: const [],
        localTombstones: const [],
        incoming: incoming,
        localExportedAt: t0,
      );
      expect(newer.settingsTakenFromRemote, isTrue);

      final older = DataMerge.merge(
        local: const [],
        localTombstones: const [],
        incoming: incoming,
        localExportedAt: t0.add(const Duration(hours: 2)),
      );
      expect(older.settingsTakenFromRemote, isFalse);
    });

    test('专注记录跟着一起合并回来', () {
      final result = DataMerge.merge(
        local: const [],
        localTombstones: const [],
        incoming: DataBundle(
          exportedAt: t0,
          tasks: const [],
          tombstones: const [],
          tags: const [],
          tagColors: const {},
          reminderMode: 0,
          alarmTheme: 'tianyi',
          focusSessions: [makeSession(startedAt: t0)],
        ),
      );
      expect(result.focusSessions.single.uid, 's1');
    });
  });
}
