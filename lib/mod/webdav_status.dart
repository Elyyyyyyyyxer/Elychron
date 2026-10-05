/// ===== 全平台同步：把"同步结果"变成界面上的一句话 =====
///
/// 为什么要单独一个文件：同步结果的原话是给日志看的 ——
/// `两边都有改动，已合并（新增 3 条，更新 1 条，删除 0 条，保留 2 条）`，
/// 直接当大标题显示又长又难读，而且里面一半是"删除 0 条"这种噪音。
///
/// 这里把它拆成 **一句大字结论 + 一行具体细节**，界面只负责摆位置：
///
///   结论：已合并两边改动
///   细节：新增 3 条 · 更新 1 条
///
/// 全是纯函数（不碰 GetX、不碰 Hive、不碰网络），单测直接钉。
library;

/// 状态种类：界面据此决定那个小圆点/字是什么颜色
enum SyncStatusKind {
  /// 从没同步过
  never,

  /// 正在同步
  syncing,

  /// 正常（上次成功了）
  ok,

  /// 上次失败
  failed,

  /// 自动同步关着
  paused,
}

/// 一句话状态（界面直接摆）
class SyncStatusView {
  /// 状态种类（配色用）
  final SyncStatusKind kind;

  /// 大字结论，例如「已是最新」
  final String headline;

  /// 时间行，例如「上次同步 今天 14:03」
  final String timeLine;

  /// 具体细节，例如「没有传输」。没有就空串（界面不占位）
  final String detail;

  const SyncStatusView(this.kind, this.headline, this.timeLine, this.detail);
}

/// 结论映射表：**同步结果原话的前缀 → 大字结论**。
///
/// 顺序有意义（先匹配到的赢），所以长的、具体的放前面。
/// 表里没命中的（比如将来新加的失败文案）会退化成「同步完成」+ 原话，
/// 不会把信息吞掉。
const List<(String, String)> _headlineRules = <(String, String)>[
  ('已是最新', '已是最新'),
  ('已从网盘取回最新数据', '已取回云端改动'),
  ('已把本机数据传到网盘', '已上传本机数据'),
  ('两边都有改动，已合并', '已合并两边改动'),
  ('同步失败', '同步失败'),
  ('附件没传完', '附件没传完'),
];

/// 时间行：今天/昨天只给时:分，更早给 月-日 时:分。
///
/// [now] 只为单测能钉住"今天"，正常调用不用传。
String formatSyncTime(DateTime time, {DateTime? now}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final at = now ?? DateTime.now();
  final hm = two(time.hour) + ':' + two(time.minute);
  final sameDay =
      time.year == at.year && time.month == at.month && time.day == at.day;
  if (sameDay) return '今天 ' + hm;
  final yesterday = at.subtract(const Duration(days: 1));
  final isYesterday = time.year == yesterday.year &&
      time.month == yesterday.month &&
      time.day == yesterday.day;
  if (isYesterday) return '昨天 ' + hm;
  return two(time.month) + '-' + two(time.day) + ' ' + hm;
}

/// 把同步结果原话拆成界面上要的那三行。
///
/// [running] 优先于一切：正在跑的时候，上一轮的结果已经不是"当前状态"了，
/// 这时候还显示「同步失败」会让用户以为这一轮又炸了。
SyncStatusView describeSyncStatus({
  required bool enabled,
  required bool running,
  required DateTime? lastSyncAt,
  required String lastSummary,
  required bool lastFailed,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final timeLine =
      lastSyncAt == null ? '还没同步过' : '上次同步 ' + formatSyncTime(lastSyncAt, now: at);

  if (running) {
    return SyncStatusView(SyncStatusKind.syncing, '正在同步…', timeLine, '');
  }

  if (!enabled) {
    // 关着的时候"当前状态"就是暂停。上一轮的结果还是要留着 ——
    // 尤其是上次失败了的话，那正是用户可能关掉它的原因。
    return SyncStatusView(
      SyncStatusKind.paused,
      '已暂停',
      timeLine,
      lastSummary.isEmpty ? '自动同步关着，只能点下面手动同步一次' : lastSummary,
    );
  }

  if (lastFailed) {
    return SyncStatusView(
      SyncStatusKind.failed,
      '同步失败',
      timeLine,
      _stripLeading(lastSummary, '同步失败'),
    );
  }

  if (lastSummary.isEmpty) {
    return lastSyncAt == null
        ? SyncStatusView(
            SyncStatusKind.never, '还没同步过', timeLine, '点下面的按钮先同步一次')
        : SyncStatusView(SyncStatusKind.ok, '已同步', timeLine, '');
  }

  for (final rule in _headlineRules) {
    if (lastSummary.startsWith(rule.$1)) {
      return SyncStatusView(
        SyncStatusKind.ok,
        rule.$2,
        timeLine,
        formatSyncDetail(lastSummary.substring(rule.$1.length)),
      );
    }
  }
  // 表里没有的新文案：不猜，原话照给（宁可啰嗦，不要丢信息）
  return SyncStatusView(SyncStatusKind.ok, '同步完成', timeLine, lastSummary);
}

/// 去掉结论后面紧跟的标点（`同步失败：xxx` → `xxx`）
String _stripLeading(String text, String prefix) {
  var rest = text;
  if (rest.startsWith(prefix)) rest = rest.substring(prefix.length);
  return formatSyncDetail(rest);
}

/// 细节行：清标点 → 拆括号 → 压计数。
///
/// 例：
///   `（新增 3 条，更新 1 条，删除 0 条，保留 2 条）` → `新增 3 条 · 更新 1 条 · 保留 2 条`
///   `，上传 3 个文件`                                → `上传 3 个文件`
///   `（新增 1 条），上传 3 个文件`                    → `新增 1 条 · 上传 3 个文件`
String formatSyncDetail(String raw) {
  var text = raw.trim();
  // 结论和细节之间可能是 '：' 或 '，'（不同调用点写法不一样，统一吃掉）
  while (text.isNotEmpty && _leadingPunctuation.contains(text.substring(0, 1))) {
    text = text.substring(1).trim();
  }
  if (text.isEmpty) return '';

  var head = text;
  var tail = '';
  if (head.startsWith('（')) {
    final end = head.indexOf('）');
    // end > 0：找得到配对的右括号才拆；只有一个孤零零的左括号就原样给
    if (end > 0) {
      tail = head.substring(end + 1).trim();
      head = head.substring(1, end).trim();
      while (tail.isNotEmpty && _leadingPunctuation.contains(tail.substring(0, 1))) {
        tail = tail.substring(1).trim();
      }
    }
  }

  final parts = <String>[];
  final inner = compactCounts(head);
  if (inner.isNotEmpty) parts.add(inner);
  if (tail.isNotEmpty) parts.add(tail.replaceAll('），', '） · '));
  return parts.join(' · ');
}

const Set<String> _leadingPunctuation = <String>{'：', ':', '，', ',', '。', ' '};

/// 合并结果里的计数：把 `0 条` 那几项去掉，分隔符从 `，` 换成 `·`。
///
/// 「删除 0 条」「保留 0 条」这种对用户是纯噪音 —— 它会让人以为
/// "同步把我东西删了"，实际上那只是在报"没删"。
String compactCounts(String text) {
  if (!text.contains('条')) return text;
  final kept = <String>[];
  for (final rawPart in text.split('，')) {
    final part = rawPart.trim();
    if (part.isEmpty) continue;
    final match = RegExp(r'^(新增|更新|删除|保留)\s*(\d+)\s*条').firstMatch(part);
    if (match != null && match.group(2) == '0') continue;
    kept.add(part);
  }
  return kept.join(' · ');
}
