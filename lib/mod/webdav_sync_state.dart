import 'dart:convert';

/// ===== 跨设备同步的"清单"与决策（W1）=====
///
/// 用户要求（2026-09-21）：
/// 「有没有办法做一个数据校验？能够做到不下载全部文件但也可以确认数据是否更新，
///   更新过的再进行同步操作，节约流量」
///
/// 有，而且分两层 —— 这一层是**省流量的核心**：
///
/// 第一层（最便宜，见 WebDavClient.propfind）：只问远端文件的 ETag/时间/大小，
///   一个请求几十字节，对不上才继续。
///
/// 第二层（本文件）：远端放一个几百字节的 manifest.json ——
///   { revision, updatedAt, deviceId, sha256, bytes, devices: [...] }
///   拉这个小文件（几百字节），比对 revision：
///     · 与本机"上次同步到的 revision"一致 → **整包根本不下载** ✓
///     · 不一致 → 再决定是拉、是推、还是双边合并（merge）
///
/// 「本机改没改」也要有个依据：本机每次落库后算一次 revision（内容哈希），
/// 与"上次推出去的 revision"不同就说明本机有未同步的改动。
///
/// 这样一来：**没有改动的一轮同步 = 一个 PROPFIND + 一个几百字节的 GET** ✓
class RemoteManifest {
  /// 整包内容的哈希（内容变了它才变）—— 这是"数据是否更新"的唯一判据
  final String revision;

  /// 这份清单是什么时候写的
  final DateTime updatedAt;

  /// 写它的设备
  final String deviceId;

  /// 整包的大小（用来显示"要传多少"）
  final int bytes;

  /// 各设备最后一次写入的状态（列表一次就知道"谁更新了"，不用下载整包）
  final List<DeviceStamp> devices;

  const RemoteManifest({
    required this.revision,
    required this.updatedAt,
    this.deviceId = '',
    this.bytes = 0,
    this.devices = const <DeviceStamp>[],
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'revision': revision,
        'updatedAt': updatedAt.toIso8601String(),
        'deviceId': deviceId,
        'bytes': bytes,
        'devices': devices.map((DeviceStamp item) => item.toJson()).toList(),
      };

  static RemoteManifest? fromJson(Map<String, dynamic> json) {
    final revision = json['revision']?.toString() ?? '';
    if (revision.isEmpty) return null;
    final stamps = <DeviceStamp>[];
    final rawList = json['devices'];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          final stamp = DeviceStamp.fromJson(Map<String, dynamic>.from(item));
          if (stamp != null) stamps.add(stamp);
        }
      }
    }
    return RemoteManifest(
      revision: revision,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      deviceId: json['deviceId']?.toString() ?? '',
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      devices: stamps,
    );
  }

  static RemoteManifest? decode(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  List<int> encode() => utf8.encode(jsonEncode(toJson()));
}

/// 一台设备的状态戳
class DeviceStamp {
  final String deviceId;
  final String name;
  final DateTime updatedAt;
  final String revision;

  const DeviceStamp({
    required this.deviceId,
    required this.name,
    required this.updatedAt,
    required this.revision,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'deviceId': deviceId,
        'name': name,
        'updatedAt': updatedAt.toIso8601String(),
        'revision': revision,
      };

  static DeviceStamp? fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId']?.toString() ?? '';
    if (deviceId.isEmpty) return null;
    return DeviceStamp(
      deviceId: deviceId,
      name: json['name']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      revision: json['revision']?.toString() ?? '',
    );
  }
}

/// 这一轮该干什么
enum SyncAction {
  /// 两端都没变 → **什么都不传**（省流量的目标状态）
  upToDate,

  /// 只有远端变了 → 下载整包
  pull,

  /// 只有本机变了 → 上传整包
  push,

  /// 两边都变了 → 都拉回来合并（合并完再推）
  merge,
}

/// 决策（**纯函数**，有单测）
///
/// [remoteRevision] 为 null 表示远端还没有数据（第一次同步）。
/// [lastSyncedRevision] 是本机"上次同步到的那个 revision"，
/// [localRevision] 是本机当前内容的 revision（和 lastSynced 不同 = 本机有未同步改动）。
SyncAction decideSyncAction({
  required String? localRevision,
  required String? remoteRevision,
  required String? lastSyncedRevision,
}) {
  final localDirty =
      localRevision != null && localRevision != lastSyncedRevision;

  // 远端从来没同步过（第一次）
  if (remoteRevision == null || remoteRevision.isEmpty) {
    return localDirty ? SyncAction.push : SyncAction.upToDate;
  }
  final remoteChanged = remoteRevision != lastSyncedRevision;

  if (!remoteChanged && !localDirty) return SyncAction.upToDate;
  if (remoteChanged && !localDirty) return SyncAction.pull;
  if (!remoteChanged && localDirty) return SyncAction.push;
  return SyncAction.merge;
}

/// 内容哈希（revision 就用它）
///
/// 用 Dart 自带的 Object.hash 拼不够稳（不同进程可能不同），
/// 所以用一段**固定算法**的简单哈希：够快、够稳、跨平台一致。
/// 目的不是抗碰撞（那是 sha256 的事），而是"内容变了 revision 就变"。
String contentRevision(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  const int mask = 0xFFFFFFFFFFFFFFFF;
  for (final byte in bytes) {
    hash = (hash ^ byte) & mask;
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0') +
      '-' +
      bytes.length.toRadixString(16);
}
