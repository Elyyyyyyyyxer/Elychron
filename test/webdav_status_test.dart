import 'package:celechron/mod/webdav_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// 这些断言钉的是**界面上那三行字**：大字结论 / 时间行 / 细节。
///
/// 为什么值得单独测：同步结果的原话来自网络层与合并层两处，
/// 拼接规则（`已把本机数据传到网盘` + `，上传 3 个文件`）稍一改动
/// 就可能变成大字标题里塞一长串括号，而那种问题只有真机上才看得见。
void main() {
  SyncStatusView describe({
    bool enabled = true,
    bool running = false,
    DateTime? lastSyncAt,
    String lastSummary = '',
    bool lastFailed = false,
    DateTime? now,
  }) =>
      describeSyncStatus(
        enabled: enabled,
        running: running,
        lastSyncAt: lastSyncAt,
        lastSummary: lastSummary,
        lastFailed: lastFailed,
        now: now,
      );

  final at = DateTime(2026, 9, 29, 14, 3);
  final now = DateTime(2026, 9, 29, 20, 0);

  group('describeSyncStatus', () {
    test('从没同步过', () {
      final view = describe(now: now);
      expect(view.kind, SyncStatusKind.never);
      expect(view.headline, '还没同步过');
      expect(view.timeLine, '还没同步过');
      expect(view.detail, '点下面的按钮先同步一次');
    });

    test('正在同步时，上一轮的失败不显示', () {
      final view = describe(
        running: true,
        lastSyncAt: at,
        lastSummary: '同步失败：连接超时',
        lastFailed: true,
        now: now,
      );
      expect(view.kind, SyncStatusKind.syncing);
      expect(view.headline, '正在同步…');
      expect(view.detail, isEmpty);
    });

    test('已暂停：留着上一轮的结果', () {
      final view = describe(
        enabled: false,
        lastSyncAt: at,
        lastSummary: '已是最新，没有传输',
        now: now,
      );
      expect(view.kind, SyncStatusKind.paused);
      expect(view.headline, '已暂停');
      expect(view.detail, '已是最新，没有传输');
    });

    test('已暂停且从没同步过：给一句能操作的提示', () {
      final view = describe(enabled: false, now: now);
      expect(view.headline, '已暂停');
      expect(view.detail, '自动同步关着，只能点下面手动同步一次');
    });

    test('失败：去掉结论里的重复前缀', () {
      final view = describe(
        lastSyncAt: at,
        lastSummary: '同步失败：无法连接服务器（网络不通）',
        lastFailed: true,
        now: now,
      );
      expect(view.kind, SyncStatusKind.failed);
      expect(view.headline, '同步失败');
      expect(view.detail, '无法连接服务器（网络不通）');
    });

    test('已是最新：细节只留「没有传输」', () {
      final view = describe(
        lastSyncAt: at,
        lastSummary: '已是最新，没有传输',
        now: now,
      );
      expect(view.kind, SyncStatusKind.ok);
      expect(view.headline, '已是最新');
      expect(view.timeLine, '上次同步 今天 14:03');
      expect(view.detail, '没有传输');
    });

    test('上传：没有细节就不显示细节行', () {
      final view = describe(
        lastSyncAt: at,
        lastSummary: '已把本机数据传到网盘',
        now: now,
      );
      expect(view.headline, '已上传本机数据');
      expect(view.detail, isEmpty);
    });

    test('上传 + 附件：逗号被吃掉，剩下文件数', () {
      final view = describe(
        lastSyncAt: at,
        lastSummary: '已把本机数据传到网盘，上传 3 个文件',
        now: now,
      );
      expect(view.headline, '已上传本机数据');
      expect(view.detail, '上传 3 个文件');
    });

    test('取回 + 合并计数：0 条被压掉', () {
      final view = describe(
        lastSyncAt: at,
        lastSummary: '已从网盘取回最新数据（新增 3 条，更新 1 条，删除 0 条，保留 0 条）',
        now: now,
      );
      expect(view.headline, '已取回云端改动');
      expect(view.detail, '新增 3 条 · 更新 1 条');
    });

    test('合并 + 附件：括号和尾巴都在', () {
      final view = describe(
        lastSyncAt: at,
        lastSummary: '两边都有改动，已合并（新增 1 条，更新 0 条，删除 0 条，保留 4 条），上传 2 个文件',
        now: now,
      );
      expect(view.headline, '已合并两边改动');
      expect(view.detail, '新增 1 条 · 保留 4 条 · 上传 2 个文件');
    });

    test('附件没传完：结论留原话', () {
      final view = describe(
        lastSyncAt: at,
        lastSummary: '已把本机数据传到网盘，附件没传完',
        now: now,
      );
      expect(view.headline, '已上传本机数据');
      expect(view.detail, '附件没传完');
    });

    test('没见过的文案：原话照给，不吞信息', () {
      final view = describe(
        lastSyncAt: at,
        lastSummary: '云端没有数据，已把本机数据作为第一份上传',
        now: now,
      );
      expect(view.headline, '同步完成');
      expect(view.detail, '云端没有数据，已把本机数据作为第一份上传');
    });

    test('有记录但没摘要：不说「还没同步过」', () {
      final view = describe(lastSyncAt: at, now: now);
      expect(view.kind, SyncStatusKind.ok);
      expect(view.headline, '已同步');
      expect(view.timeLine, '上次同步 今天 14:03');
    });
  });

  group('formatSyncTime', () {
    test('今天 / 昨天 / 更早', () {
      expect(formatSyncTime(DateTime(2026, 9, 29, 9, 5), now: now), '今天 09:05');
      expect(formatSyncTime(DateTime(2026, 9, 28, 23, 59), now: now), '昨天 23:59');
      expect(formatSyncTime(DateTime(2026, 9, 20, 7, 0), now: now), '09-20 07:00');
    });
  });

  group('compactCounts', () {
    test('不是计数就原样返回', () {
      expect(compactCounts('上传 3 个文件'), '上传 3 个文件');
    });

    test('全是 0 就变空串（界面据此不显示细节行）', () {
      expect(compactCounts('新增 0 条，更新 0 条，删除 0 条，保留 0 条'), isEmpty);
    });
  });
}
