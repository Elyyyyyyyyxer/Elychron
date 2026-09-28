import 'dart:convert';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/webdav_client.dart';
import 'package:celechron/mod/webdav_sync_state.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:get/get.dart';

/// ===== 全平台同步（W2）：WebDAV 上的实际读写 =====
///
/// 复用已经造好的那一整套（DataBundle 打包 / DataMerge 合并 / 墓碑 / 冲突选择），
/// 这里只负责"怎么跟网盘打交道"，合并口径一行都不重写。
///
/// 远端目录结构（全部由程序自动创建，用户不用管）：
///   Elychron/
///     meta.json      几百字节的清单（revision + 各设备状态戳）← 省流量的关键
///     bundle.json    整包数据（改动时才会上传/下载）
///     devices/<id>.json  每台设备最后一次写入的状态
///
/// 一轮同步的顺序（**从便宜到贵**，任何一步能断定"不用继续"就立刻收工）：
///   1. PROPFIND meta.json → 拿 ETag/时间/大小，和本机记的一致 → **收工**（几十字节）
///   2. GET meta.json（几百字节）→ 比 revision → upToDate → **收工**（几百字节）
///   3. 需要时才 GET/PUT bundle.json（整包）
class WebDavSync {
  WebDavSync(
    this._client, {
    required this.deviceId,
    required this.deviceName,
  });

  final WebDavClient _client;
  final String deviceId;
  final String deviceName;

  static const String rootDir = 'Elychron';
  static const String manifestFile = 'meta.json';
  static const String bundleFile = 'bundle.json';
  static const String devicesDir = 'devices';

  static const String _kLastRevisionKey = 'webdavLastRevision';
  static const String _kLastFingerprintKey = 'webdavLastManifestFingerprint';

  DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  String get _manifestPath => rootDir + '/' + manifestFile;
  String get _bundlePath => rootDir + '/' + bundleFile;
  String get _devicePath =>
      rootDir + '/' + devicesDir + '/' + deviceId + '.json';

  // ------------------------------------------------------------ 本地记录

  String? get lastSyncedRevision =>
      _db?.optionsBox.get(_kLastRevisionKey) as String?;
  String? get lastManifestFingerprint =>
      _db?.optionsBox.get(_kLastFingerprintKey) as String?;

  Future<void> _remember(RemoteManifest manifest, String fingerprint) async {
    try {
      final box = _db?.optionsBox;
      await box?.put(_kLastRevisionKey, manifest.revision);
      await box?.put(_kLastFingerprintKey, fingerprint);
    } catch (_) {}
  }

  // ------------------------------------------------------------ 自检

  /// 连通性自检：**用户看到的是一句人话结论**
  ///
  /// 做四件事：探测目录 → 建目录 → 写一个探针文件 → 读回来比对 → 删掉。
  /// 只有四步都过，才说明"这个网盘能用来同步"。
  ///
  /// ===== 顺带兜住一个真坑：坚果云的用户名**必须全小写** =====
  ///
  /// 实测（2026-09-28，真账号）：
  ///   tixerofficial@outlook.com → 207 ✓
  ///   TixerOfficial@outlook.com → 401 ✗（服务器 Basic realm="nutstore"）
  /// 用户从网页复制邮箱时首字母常常是大写 —— 密码明明对，却怎么都连不上。
  ///
  /// 但不能**无条件**小写：Nextcloud 那类自建服务的用户名是大小写敏感的，
  /// 乱改反而会把本来能用的账号改坏。所以：**先按原样试，401 再试小写**，
  /// 成功了就把 username 切过去（后续请求都走它）。
  Future<WebDavCheck> selfCheck() async {
    var result = await _selfCheckOnce();
    final lower = _client.username.toLowerCase();
    if (!result.ok &&
        result.message.contains('应用密码') &&
        _client.username != lower) {
      final original = _client.username;
      _client.username = lower;
      final retry = await _selfCheckOnce();
      if (retry.ok) {
        return const WebDavCheck(true, '连接正常，可以同步（用户名已自动转成小写）');
      }
      _client.username = original;
      result = retry;
    }
    return result;
  }

  Future<WebDavCheck> _selfCheckOnce() async {
    try {
      await _client.propfind(rootDir, depth: 0);
    } on WebDavException catch (error) {
      if (error.status != 404) return WebDavCheck(false, error.message);
      // 404 = 目录还没建，正常，继续
    }
    try {
      await _client.ensureDirectory(rootDir);
      final path = rootDir + '/.probe';
      final payload =
          utf8.encode('elychron-probe-' + DateTime.now().toIso8601String());
      await _client.put(path, payload);
      final back = await _client.get(path);
      await _client.delete(path);
      if (back == null) return const WebDavCheck(false, '写进去了但读不回来，这个网盘可能不支持');
      if (!_sameBytes(back, payload))
        return const WebDavCheck(false, '读回来的内容和写进去的不一样');
      return const WebDavCheck(true, '连接正常，可以同步');
    } on WebDavException catch (error) {
      return WebDavCheck(false, error.message);
    } catch (error) {
      return WebDavCheck(false, '自检失败：' + error.toString());
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ------------------------------------------------------------ 同步

  /// 真正的同步
  ///
  /// [buildLocal] 由调用方提供（用 DataBackup.currentBundle 打整包），
  /// [applyRemote] 由调用方提供（用 mergeIncomingBundle 合并进来）——
  /// 这样这个类不依赖 GetX 里的任务列表，也能被单测替换掉。
  Future<WebDavSyncResult> sync({
    required Future<DataBundle> Function() buildLocal,
    required Future<void> Function(DataBundle incoming) applyRemote,
    String? localRevision,
  }) async {
    try {
      await _client.ensureDirectory(rootDir);
      await _client.ensureDirectory(rootDir + '/' + devicesDir);

      // 第一层：只问元数据（几十字节）
      final entry = await _client.stat(_manifestPath);
      final fingerprint = entry?.fingerprint;
      if (fingerprint != null &&
          fingerprint == lastManifestFingerprint &&
          localRevision != null &&
          localRevision == lastSyncedRevision) {
        return const WebDavSyncResult(SyncAction.upToDate, '已是最新，没有传输');
      }

      // 第二层：拉清单（几百字节）
      RemoteManifest? manifest;
      if (entry != null) {
        final bytes = await _client.get(_manifestPath);
        if (bytes != null) manifest = RemoteManifest.decode(bytes);
      }

      final action = decideSyncAction(
        localRevision: localRevision,
        remoteRevision: manifest?.revision,
        lastSyncedRevision: lastSyncedRevision,
      );

      if (action == SyncAction.upToDate) {
        if (manifest != null && fingerprint != null) {
          await _remember(manifest, fingerprint);
        }
        return const WebDavSyncResult(SyncAction.upToDate, '已是最新，没有传输');
      }

      // 需要远端数据就下载整包并合并
      if (action == SyncAction.pull || action == SyncAction.merge) {
        final bytes = await _client.get(_bundlePath);
        if (bytes != null) {
          final incoming = DataBundle.decode(utf8.decode(bytes));
          if (incoming != null) await applyRemote(incoming);
        }
      }

      // 需要上传（push / merge）
      if (action == SyncAction.push || action == SyncAction.merge) {
        final bundle = await buildLocal();
        final encoded = utf8.encode(bundle.encode());
        final revision = contentRevision(encoded);
        await _client.put(_bundlePath, encoded);
        final now = DateTime.now();
        final next = RemoteManifest(
          revision: revision,
          updatedAt: now,
          deviceId: deviceId,
          bytes: encoded.length,
          devices: <DeviceStamp>[
            ...?manifest?.devices
                .where((DeviceStamp item) => item.deviceId != deviceId),
            DeviceStamp(
              deviceId: deviceId,
              name: deviceName,
              updatedAt: now,
              revision: revision,
            ),
          ],
        );
        final manifestBytes = next.encode();
        await _client.put(_manifestPath, manifestBytes);
        await _client.put(_devicePath, manifestBytes);
        await _remember(next, contentRevision(manifestBytes));
      } else if (manifest != null && fingerprint != null) {
        // 只拉不推：把远端那次的状态记下来，下次就能走"全都不用传"
        await _remember(manifest, fingerprint);
      }

      final message = switch (action) {
        SyncAction.pull => '已从网盘取回最新数据',
        SyncAction.push => '已把本机数据传到网盘',
        SyncAction.merge => '两边都有改动，已合并',
        SyncAction.upToDate => '已是最新，没有传输',
      };
      return WebDavSyncResult(action, message);
    } on WebDavException catch (error) {
      return WebDavSyncResult(SyncAction.upToDate, error.message, failed: true);
    } catch (error) {
      return WebDavSyncResult(SyncAction.upToDate, '同步失败：' + error.toString(),
          failed: true);
    }
  }
}

/// 自检结果（给界面直接显示）
class WebDavCheck {
  final bool ok;
  final String message;
  const WebDavCheck(this.ok, this.message);
}

/// 同步结果（给界面直接显示）
class WebDavSyncResult {
  final SyncAction action;
  final String message;
  final bool failed;
  const WebDavSyncResult(this.action, this.message, {this.failed = false});
}
