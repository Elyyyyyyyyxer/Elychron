import 'dart:async';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/lan_sync_merge.dart';
import 'package:celechron/mod/webdav_config.dart';
import 'package:celechron/mod/webdav_sync.dart';
import 'package:celechron/mod/webdav_sync_state.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/data_backup.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// ===== 全平台同步（W3）：真正跑一轮同步 =====
///
/// 这一层很薄，只干三件事：
///   1. 把 WebDavSync 需要的两个回调接上（打包 / 合并）—— 合并口径
///      直接复用局域网同步那份 `mergeIncomingBundle`，不重写第二遍
///      （两处各写一份，迟早不一致，那才是同步事故的来源）；
///   2. 同时只跑一轮（否则手机上很容易出现两次同步互相覆盖）；
///   3. 把结果记进配置，供界面显示"上次同步"。
class WebDavSyncService {
  WebDavSyncService._();

  static final WebDavSyncService instance = WebDavSyncService._();

  /// 界面监听它刷新（同步结束后要更新副标题）
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool _running = false;
  Timer? _timer;
  Timer? _pullTimer;
  StreamSubscription<List<Task>>? _taskSub;

  bool get running => _running;

  Future<WebDavSyncResult>? _current;

  /// 跑一轮同步。正在跑就直接返回那一轮的 Future（不排队、不叠加）。
  /// 没配置好就返回 null（界面据此提示"先去设置"）。
  Future<WebDavSyncResult?> syncNow() async {
    if (_running) return _current;
    final sync = WebDavConfig.buildSync();
    if (sync == null) return null;
    final future = _run(sync);
    _current = future;
    return future;
  }

  Future<WebDavSyncResult> _run(WebDavSync sync) async {
    _running = true;
    revision.value++;
    try {
      final db = Get.find<DatabaseHelper>(tag: 'db');
      final taskList = Get.find<RxList<Task>>(tag: 'taskList');
      final result = await sync.sync(
        buildLocal: () => DataBackup.currentBundle(db, taskList.toList()),
        applyRemote: (incoming) async {
          // 合并前会自己落一份本地备份（见 mergeIncomingBundle 内部），
          // 万一合并出意外，用户的原始数据还在。
          await mergeIncomingBundle(incoming: incoming);
        },
      );
      await WebDavConfig.recordSync(result.message, failed: result.failed);
      return result;
    } catch (error) {
      final message = '同步失败：' + error.toString();
      await WebDavConfig.recordSync(message, failed: true);
      return WebDavSyncResult(SyncAction.upToDate, message, failed: true);
    } finally {
      _running = false;
      revision.value++;
    }
  }

  /// 数据一变就排一轮同步（延迟几秒合并连着的多次改动，比如批量导入）。
  /// 只有用户明确开启了同步才会真的跑。
  void scheduleSync({Duration delay = const Duration(seconds: 8)}) {
    if (!WebDavConfig.enabled || !WebDavConfig.isConfigured) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      syncNow();
    });
  }

  void cancelScheduled() {
    _timer?.cancel();
    _timer = null;
  }

  // ------------------------------------------------------------ 自动同步

  /// 开关（界面上那个"自动同步"）
  Future<void> setEnabled(bool value) async {
    await WebDavConfig.setEnabled(value);
    if (value) {
      startAutoSync();
    } else {
      stopAutoSync();
    }
    revision.value++;
  }

  /// 开始自动同步。没配好、或用户关掉了，就什么都不做（幂等，可以重复调）。
  ///
  /// 两个触发点，与局域网同步同一套口径：
  /// - **待办列表一变**就排一轮（其余用户数据走 notifyDataChanged）；
  /// - 每 10 分钟**主动问一次远端**——只在别的设备上改过时，本机没有任何
  ///   本地事件可听，只能靠这个定时器，否则"手机上改了，电脑半天不更新"。
  void startAutoSync() {
    if (!WebDavConfig.enabled || !WebDavConfig.isConfigured) return;
    if (!WebDavConfig.loaded) return;
    final list = _taskListOf();
    _taskSub ??= list?.listen((_) => scheduleSync());
    _pullTimer ??= Timer.periodic(const Duration(minutes: 10), (_) {
      if (!WebDavConfig.enabled) return;
      syncNow();
    });
  }

  void stopAutoSync() {
    _taskSub?.cancel();
    _taskSub = null;
    _pullTimer?.cancel();
    _pullTimer = null;
    cancelScheduled();
  }

  RxList<Task>? _taskListOf() {
    try {
      return Get.find<RxList<Task>>(tag: 'taskList');
    } catch (_) {
      return null;
    }
  }

  /// 界面上"上次同步：今天 14:03 · 已是最新，没有传输"
  static String describeLastSync() {
    if (!WebDavConfig.isConfigured) return '还没设置';
    final at = WebDavConfig.lastSyncAt;
    if (at == null) return '还没同步过';
    final text = formatTime(at);
    final summary = WebDavConfig.lastSummary;
    if (summary.isEmpty) return text;
    return text + ' · ' + summary;
  }

  static String formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final now = DateTime.now();
    final hm = two(time.hour) + ':' + two(time.minute);
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    if (sameDay) return '今天 ' + hm;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = time.year == yesterday.year &&
        time.month == yesterday.month &&
        time.day == yesterday.day;
    if (isYesterday) return '昨天 ' + hm;
    return two(time.month) + '-' + two(time.day) + ' ' + hm;
  }
}
