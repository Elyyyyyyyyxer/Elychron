import 'dart:async';
import 'dart:convert';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/focus_device.dart';
import 'package:celechron/mod/lan_sync_merge.dart';
import 'package:celechron/mod/webdav_client.dart';
import 'package:celechron/mod/webdav_files.dart';
import 'package:celechron/mod/webdav_config.dart';
import 'package:celechron/mod/webdav_sync.dart';
import 'package:celechron/mod/webdav_status.dart';
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

  /// 被网盘限流（503）之后的静默期：这段时间里**自动**轮询不再发请求。
  ///
  /// 坚果云的 503 是限流保护而不是宕机（见 webdav_client._explain 的注释），
  /// 而"每 3 分钟去撞一次"只会让限流更久。手动点「立即同步」/下拉刷新不受影响 ——
  /// 那是用户明确要看结果的动作。
  DateTime? _backoffUntil;
  StreamSubscription<List<Task>>? _taskSub;

  bool get running => _running;

  Future<WebDavSyncResult>? _current;

  /// 跑一轮同步。正在跑就直接返回那一轮的 Future（不排队、不叠加）。
  /// 没配置好就返回 null（界面据此提示"先去设置"）。
  Future<WebDavSyncResult?> syncNow() async {
    if (_running) return _current;
    final client = WebDavConfig.buildClient();
    if (client == null) return null;
    final sync = WebDavSync(
      client,
      deviceId: WebDavConfig.deviceIdOfThisDevice,
      deviceName: FocusDevice.current,
    );
    final future = _run(sync, client);
    _current = future;
    return future;
  }

  Future<WebDavSyncResult> _run(WebDavSync sync, WebDavClient client) async {
    _running = true;
    revision.value++;
    try {
      final db = Get.find<DatabaseHelper>(tag: 'db');
      final taskList = Get.find<RxList<Task>>(tag: 'taskList');
      // ===== 本机当前内容的 revision（必须真的算出来）=====
      //
      // 一开始这里没传 localRevision，于是 decideSyncAction 的 localDirty
      // **永远是 false** —— 本机自己的改动永远不算"有改动"，结果是：
      //   1. 最省流量的第一层（指纹 + revision 都对得上就直接收工）永远不生效；
      //   2. 本机改的东西要等远端也变了才会被带上去。
      // 用户看到的现象就是"电脑端同步了个空气"。
      //
      // 代价只有一次本地 JSON 编码（没有网络请求），省流量的三层照样有效。
      final localBundle = await DataBackup.currentBundle(db, taskList.toList());
      final localRevision = contentRevision(utf8.encode(localBundle.encode()));
      var mergeSummary = '';
      final result = await sync.sync(
        buildLocal: () => DataBackup.currentBundle(db, taskList.toList()),
        applyRemote: (incoming) async {
          // 合并前会自己落一份本地备份（见 mergeIncomingBundle 内部），
          // 万一合并出意外，用户的原始数据还在。
          final summary = await mergeIncomingBundle(incoming: incoming);
          // 合并结果（新增/改了几条）原来**被丢掉了** —— 界面上只显示
          // "已从网盘取回最新数据"，用户根本看不出到底同步进来什么，
          // 于是"同步了个空气"这种怀疑无从分辨。这里把它记下来给界面看。
          mergeSummary = (summary['summary'] ?? '').toString();
        },
        localRevision: localRevision,
      );
      var message = result.message;
      if (mergeSummary.isNotEmpty &&
          (result.action == SyncAction.pull ||
              result.action == SyncAction.merge)) {
        message = message + '（' + mergeSummary + '）';
      }
      if (!result.failed) {
        final extra = await _syncFiles(client, db, taskList, result.action);
        if (extra.isNotEmpty) message = message + '，' + extra;
      }
      if (result.failed) {
        _noteFailure(message);
      } else {
        _backoffUntil = null;
      }
      await WebDavConfig.recordSync(message, failed: result.failed);
      return WebDavSyncResult(result.action, message, failed: result.failed);
    } catch (error) {
      final message = '同步失败：' + error.toString();
      _noteFailure(message);
      await WebDavConfig.recordSync(message, failed: true);
      return WebDavSyncResult(SyncAction.upToDate, message, failed: true);
    } finally {
      _running = false;
      revision.value++;
    }
  }

  // ------------------------------------------------------------ 附件本体（W4）

  /// 把附件文件本体也搬一遍。返回一句给用户看的话（没搬东西就返回空串）。
  ///
  /// 只在**确实需要**的方向上动：
  /// - 拉过对方的数据（pull / merge）→ 看看有没有哪个附件本机还没有；
  /// - 推过自己的数据（push / merge）→ 看看有没有哪个附件远端还没有。
  /// 附件是"加分项"：传不动**不该让整轮同步失败**（元数据已经同步好了），
  /// 所以这里自己吞异常，只把结果如实告诉用户。
  Future<String> _syncFiles(
    WebDavClient client,
    DatabaseHelper db,
    RxList<Task> taskList,
    SyncAction action,
  ) async {
    if (!WebDavConfig.fileSyncEnabled) return '';
    final files = WebDavFiles(client, rootDir: WebDavSync.rootDir);
    final index = WebDavFiles.decodeIndex(WebDavConfig.fileIndexRaw);
    final origin = WebDavFiles.decodeMap(WebDavConfig.fileOriginRaw);
    var fetched = 0, sent = 0, skipped = 0;
    try {
      if (action == SyncAction.pull || action == SyncAction.merge) {
        final result = await files.downloadMissing(
          db,
          taskList.toList(),
          origin: origin,
          flush: () async {
            await db.setTaskList(taskList);
            taskList.refresh();
            await WebDavFiles.flushCourseMounts(db);
          },
        );
        fetched = result.sent;
        skipped += result.skipped;
        if (result.bytes > 0) await WebDavConfig.addTraffic(down: result.bytes);
      }
      // 上传：**每次同步都跑一遍**，不看这一轮是什么动作。
      //
      // 为什么不能只在 push/merge 时跑（真机验收时发现的缺口）：
      // 用户打开"同步附件文件"开关之后，如果这段时间没有数据改动，
      // 每轮同步都是"已是最新，没有传输"—— 附件就永远上不去，
      // 另一台设备点开依然是空的。
      //
      // 每次都跑也不费流量：本地只做 stat + 查索引，不产生网络请求；
      // 只有真的多出"索引里没有"的文件时才会 PUT。
      {
        final result = await files.uploadMissing(
          db,
          taskList.toList(),
          index: index,
          origin: origin,
          maxFileBytes: WebDavConfig.maxFileBytes,
          usedThisMonth: WebDavConfig.uploadedBytesThisMonth,
          monthlyBudget: WebDavConfig.monthlyUploadBudget,
        );
        sent = result.sent;
        skipped += result.skipped;
        if (result.sent > 0) {
          await WebDavConfig.setFileIndexRaw(WebDavFiles.encodeIndex(index));
          await WebDavConfig.addTraffic(up: result.bytes);
        }
      }
      // origin 两边都可能改（下载时登记、上传时清理），统一落盘一次
      await WebDavConfig.setFileOriginRaw(
        WebDavFiles.encodeStringMap(origin),
      );
    } catch (_) {
      return '附件没传完';
    }
    final parts = <String>[];
    if (fetched > 0) parts.add('取回 ' + fetched.toString() + ' 个文件');
    if (sent > 0) parts.add('上传 ' + sent.toString() + ' 个文件');
    if (skipped > 0) {
      parts.add(skipped.toString() + ' 个附件超出大小/流量上限，没传');
    }
    return parts.join('，');
  }

  /// 数据一变就排一轮同步（延迟几秒合并连着的多次改动，比如批量导入）。
  /// 只有用户明确开启了同步才会真的跑。
  void scheduleSync({Duration delay = const Duration(seconds: 8)}) {
    if (!WebDavConfig.enabled || !WebDavConfig.isConfigured) return;
    if (!_autoAllowed) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      syncNow();
    });
  }

  /// 失败原因里带限流字样就退避一段时间（30 分钟），别一直去撞。
  void _noteFailure(String message) {
    if (message.contains('503') || message.contains('限流')) {
      _backoffUntil = DateTime.now().add(const Duration(minutes: 30));
    }
  }

  /// 现在能不能自动同步（限流静默期里返回 false）
  bool get _autoAllowed {
    final until = _backoffUntil;
    return until == null || !DateTime.now().isBefore(until);
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
  /// - 每 3 分钟**主动问一次远端**——只在别的设备上改过时，本机没有任何
  ///   本地事件可听，只能靠这个定时器，否则"手机上改了，电脑半天不更新"。
  void startAutoSync() {
    if (!WebDavConfig.enabled || !WebDavConfig.isConfigured) return;
    if (!WebDavConfig.loaded) return;
    final list = _taskListOf();
    _taskSub ??= list?.listen((_) => scheduleSync());
    // 3 分钟而不是 10 分钟：用户的原话是"一个端更新了，另一个端不能自动更新"。
    // WebDAV 没有推送通道，只能定时问；而一次"没变化"的检查只有几十到几百字节
    // （PROPFIND 看指纹 + 读 meta.json），问得勤一点远比让用户干等十分钟划算。
    _pullTimer ??= Timer.periodic(const Duration(minutes: 3), (_) {
      if (!WebDavConfig.enabled) return;
      if (!_autoAllowed) return;
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

  /// 时间的说法只保留一份（在 webdav_status.dart 里）。这里只做转发 ——
  /// 两处各写一遍的话，"昨天"和"今天"的边界迟早会出现两种结果。
  static String formatTime(DateTime time) => formatSyncTime(time);
}
