import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/mod/webdav_client.dart';
import 'package:path_provider/path_provider.dart';

/// ===== 全平台同步（W4）：附件本体走 WebDAV =====
///
/// 同步协议里附件只有 name/path/size，**二进制不过包**（见 data_sync.dart）。
/// 所以别的设备上那一行在、点开是空的 —— 这一层负责把文件本体搬过去。
///
/// 三条设计原则：
///
/// 1. **远端文件名由"来源设备上的路径"决定**（[remoteNameFor]，纯函数）。
///    两边各自算同一个名字，不需要额外的映射表；谁先传谁后传都对得上。
///    这样也天然区分了"两台设备上同名但内容不同的文件"。
/// 2. **不重复传**：本机记一份索引（远端名 → 上次传出去时的大小），
///    大小没变就跳过。文件内容改了大小没变（极少见）最多浪费一次流量，
///    传错数据的风险为零 —— 名字里不含内容指纹，这是刻意的取舍。
/// 3. **流量要有上限**：坚果云免费版每月上传 1GB。所以有单文件上限、
///    每月总量上限，超了就不传并**如实告诉用户**，而不是默默把配额跑光。
class WebDavFiles {
  WebDavFiles(this._client, {required this.rootDir});

  final WebDavClient _client;
  final String rootDir;

  static const String filesDir = 'files';

  String get _dir => rootDir + '/' + filesDir;

  String _pathOf(String name) => _dir + '/' + name;

  // ------------------------------------------------------------ 纯函数

  /// 远端文件名：`<路径哈希>_<文件名>`
  ///
  /// 为什么名字里要有那串哈希：同名文件在手机和电脑上很常见
  /// （`IMG_0001.jpg`、`简历.pdf`），而我们**不能**拿文件名当身份 ——
  /// 那样两台设备的同名不同文件会互相覆盖。用"来源设备上的绝对路径"
  /// 做哈希，两台设备各自算出来必然一致（路径就在包里的 path 字段里），
  /// 又天然不会撞。
  static String remoteNameFor(String path) {
    final normalized = path.replaceAll('\\', '/');
    final base = normalized.split('/').last;
    final safe = _sanitize(base);
    return _fnv32(normalized) + '_' + safe;
  }

  /// 只留下"能安全放进一个 URL 段"的字符；中文保留（客户端会按段编码）。
  static String _sanitize(String name) {
    final buffer = StringBuffer();
    for (final unit in name.codeUnits) {
      final isDigit = unit >= 0x30 && unit <= 0x39;
      final isUpper = unit >= 0x41 && unit <= 0x5A;
      final isLower = unit >= 0x61 && unit <= 0x7A;
      final isSafePunct = unit == 0x2E || unit == 0x5F || unit == 0x2D; // . _ -
      final isAscii = unit < 0x80;
      if (isDigit || isUpper || isLower || isSafePunct) {
        buffer.writeCharCode(unit);
      } else if (!isAscii) {
        // 中文等非 ASCII：留着（用户看得懂比什么都要紧）
        buffer.writeCharCode(unit);
      } else {
        buffer.write('_');
      }
    }
    var text = buffer.toString();
    if (text.isEmpty) text = 'file';
    // 太长的名字（安卓的 content 拷贝常常带上超长后缀）截一下，但要保住扩展名
    if (text.length > 60) {
      final dot = text.lastIndexOf('.');
      final ext =
          (dot > 0 && text.length - dot <= 8) ? text.substring(dot) : '';
      final keep = 60 - ext.length;
      if (keep > 0) text = text.substring(0, keep) + ext;
    }
    return text;
  }

  /// 32 位 FNV-1a，够短够稳（名字里还带着文件名，撞了也不会互相覆盖）
  static String _fnv32(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash = hash ^ (unit & 0xFF);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
      hash = hash ^ ((unit >> 8) & 0xFF);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// 要不要传这个文件（纯函数，单测钉着）
  ///
  /// [uploadedBytes] 是索引里记的"上次传出去时的大小"，null = 从没传过。
  static bool shouldUpload({
    required int? uploadedBytes,
    required int size,
    required int maxFileBytes,
    required int usedThisMonth,
    required int monthlyBudget,
  }) {
    if (size <= 0) return false;
    if (uploadedBytes == size) return false;
    if (maxFileBytes > 0 && size > maxFileBytes) return false;
    if (monthlyBudget > 0 && usedThisMonth + size > monthlyBudget) return false;
    return true;
  }

  /// 人话流量（界面直接用）
  static String formatBytes(int bytes) {
    if (bytes < 1024) return bytes.toString() + ' B';
    final kb = bytes / 1024;
    if (kb < 1024) return kb.toStringAsFixed(1) + ' KB';
    final mb = kb / 1024;
    if (mb < 1024) return mb.toStringAsFixed(1) + ' MB';
    return (mb / 1024).toStringAsFixed(2) + ' GB';
  }

  // ------------------------------------------------------------ 上传

  /// 把本机有、远端没有（或变了）的附件传上去。返回传了几个、传了多少字节。
  Future<WebDavFileResult> uploadMissing(
    DatabaseHelper db,
    List<Task> tasks, {
    required Map<String, int> index,
    required Map<String, String> origin,
    required int maxFileBytes,
    required int usedThisMonth,
    required int monthlyBudget,
  }) async {
    final handles = collectAttachments(db, tasks);
    if (handles.isEmpty) return const WebDavFileResult();
    await _ensureDir();
    // 顺手清掉已经不存在的路径的记录（附件删了 / 换了一台设备），
    // 免得这份映射越积越大
    final alive = <String>{
      for (final handle in handles)
        if (handle.path.isNotEmpty) handle.path,
    };
    origin.removeWhere((String path, String _) => !alive.contains(path));
    var sent = 0, bytes = 0, skipped = 0;
    for (final handle in handles) {
      final path = handle.path;
      if (path.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue; // 本机也没有（还没从对方那儿拉下来）
      final size = await file.length();
      // 这个文件是从网盘落下来的话，**继续用它在网盘上的名字**，
      // 否则会因为本地路径不同而把同一份文件重复传一遍。
      final name = origin[path] ?? remoteNameFor(path);
      final ok = shouldUpload(
        uploadedBytes: index[name],
        size: size,
        maxFileBytes: maxFileBytes,
        usedThisMonth: usedThisMonth + bytes,
        monthlyBudget: monthlyBudget,
      );
      if (!ok) {
        if (index[name] != size) skipped++;
        continue;
      }
      try {
        final raw = await file.readAsBytes();
        await _client.put(_pathOf(name), raw);
        index[name] = size;
        sent++;
        bytes += size;
      } catch (_) {
        // 单个文件失败不该让整轮同步失败：下一个接着传
        skipped++;
      }
    }
    return WebDavFileResult(sent: sent, bytes: bytes, skipped: skipped);
  }

  // ------------------------------------------------------------ 下载

  /// 把本机没有、远端有的附件取回来；取回来之后把记录里的 path 改成新路径。
  Future<WebDavFileResult> downloadMissing(
    DatabaseHelper db,
    List<Task> tasks, {
    required Map<String, String> origin,
    required Future<void> Function() flush,
  }) async {
    final handles = collectAttachments(db, tasks);
    final wanted = <String, List<AttachmentHandle>>{};
    for (final handle in handles) {
      final path = handle.path;
      if (path.isEmpty) continue;
      if (await File(path).exists()) continue; // 本机已经有了
      // 这个路径是"从网盘落下来的"话，它的网盘名字记在 origin 里；
      // 本地文件被清掉后还能按原名取回来（否则会按本地路径算出一个不存在的名字）
      final name = origin[path] ?? remoteNameFor(path);
      wanted.putIfAbsent(name, () => <AttachmentHandle>[]).add(handle);
    }
    if (wanted.isEmpty) return const WebDavFileResult();

    // 一次 PROPFIND 拿到远端有哪些文件（depth 1），再按需下载 ——
    // 免得为每个缺失的附件都发一次请求（那是"一次同步几十个请求"的来源）
    final available = await _remoteNames();
    if (available.isEmpty) return const WebDavFileResult();

    final cache = await _attachDir();
    var got = 0, bytes = 0, skipped = 0;
    for (final entry in wanted.entries) {
      if (!available.contains(entry.key)) {
        skipped += entry.value.length;
        continue;
      }
      final Uint8List? raw = await _safeGet(_pathOf(entry.key));
      if (raw == null) {
        skipped += entry.value.length;
        continue;
      }
      // 同一个远端文件可能被多条记录引用（复制待办就会这样）：
      // 只落一份磁盘，几条记录一起指向它。
      final safeName = _nameFromRemote(entry.key);
      final stamp = DateTime.now().microsecondsSinceEpoch.toString();
      final target = File(cache.path + '/' + stamp + '_' + safeName);
      await target.writeAsBytes(raw);
      origin[target.path] = entry.key;
      for (final handle in entry.value) {
        handle.setPath(target.path);
      }
      got++;
      bytes += raw.length;
    }
    if (got > 0) await flush();
    return WebDavFileResult(sent: got, bytes: bytes, skipped: skipped);
  }

  Future<List<String>> _remoteNames() async {
    try {
      final entries = await _client.propfind(_dir, depth: 1);
      return entries
          .where((WebDavEntry item) => !item.isDirectory)
          .map((WebDavEntry item) => item.path.split('/').last)
          .where((String name) => name.isNotEmpty)
          .toList();
    } on WebDavException {
      return const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  Future<Uint8List?> _safeGet(String path) async {
    try {
      final bytes = await _client.get(path);
      if (bytes == null) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureDir() async {
    try {
      await _client.ensureDirectory(_dir);
    } catch (_) {}
  }

  Future<Directory> _attachDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(docs.path + '/task_attachments');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ------------------------------------------------------------ 收集附件

  /// 待办附件 + 课程挂载资料，两处都要搬（与局域网同步同一口径）
  static List<AttachmentHandle> collectAttachments(
      DatabaseHelper db, List<Task> tasks) {
    final result = <AttachmentHandle>[];
    for (final task in tasks) {
      for (final attachment in task.attachments) {
        result.add(AttachmentHandle(
          attachment.path,
          (String next) => attachment.path = next,
        ));
      }
    }
    for (final entry in db.courseMountBox.toMap().entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      final attachments = (raw['attachments'] as List?)?.toList();
      if (attachments == null) continue;
      for (final item in attachments) {
        if (item is! Map) continue;
        result.add(AttachmentHandle(
          item['path']?.toString() ?? '',
          (String next) => item['path'] = next,
        ));
      }
    }
    return result;
  }

  /// 把课程挂载里附件路径的改动写回盒子。
  ///
  /// Hive 里存的是裸 Map，改完**必须 put 回去**才落盘（局域网同步那边也是这么做的）。
  /// 课程挂载本来就没几门课，整体重写一遍最简单，也不容易漏。
  static Future<void> flushCourseMounts(DatabaseHelper db) async {
    for (final entry in db.courseMountBox.toMap().entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      await db.courseMountBox.put(entry.key, <String, dynamic>{
        'attachments': (raw['attachments'] as List?) ?? const <dynamic>[],
        'comments': raw['comments'] ?? const <dynamic>[],
      });
    }
  }

  /// 远端文件名（`<哈希>_<文件名>`）里取出文件名部分，用来做本地落盘的名字
  static String _nameFromRemote(String remoteName) {
    final index = remoteName.indexOf('_');
    final name = index >= 0 ? remoteName.substring(index + 1) : remoteName;
    return name.isEmpty ? 'attachment' : name;
  }

  /// 索引（远端名 → 大小）存在 optionsBox 里，跟着本机走
  static Map<String, int> decodeIndex(String? raw) {
    final result = <String, int>{};
    if (raw == null || raw.isEmpty) return result;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          final size = value is num ? value.toInt() : int.tryParse('$value');
          if (size != null) result[key.toString()] = size;
        });
      }
    } catch (_) {}
    return result;
  }

  /// 本机路径 → 网盘名字 这份映射的编解码（与索引同一套容错口径：坏了当没有）
  static Map<String, String> decodeMap(String? raw) {
    final result = <String, String>{};
    if (raw == null || raw.isEmpty) return result;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          final text = value?.toString() ?? '';
          if (text.isNotEmpty) result[key.toString()] = text;
        });
      }
    } catch (_) {}
    return result;
  }

  static String encodeStringMap(Map<String, String> map) {
    try {
      return jsonEncode(map);
    } catch (_) {
      return '{}';
    }
  }

  static String encodeIndex(Map<String, int> index) {
    try {
      return jsonEncode(index);
    } catch (_) {
      return '{}';
    }
  }
}

/// 一条附件记录的可写句柄（待办的字段 / 课程挂载里的 map，两处形状不同）
class AttachmentHandle {
  AttachmentHandle(this.path, this._apply);

  String path;
  final void Function(String next) _apply;

  void setPath(String next) {
    path = next;
    _apply(next);
  }
}

/// 一轮附件同步的结果
class WebDavFileResult {
  final int sent;
  final int bytes;
  final int skipped;
  const WebDavFileResult({this.sent = 0, this.bytes = 0, this.skipped = 0});

  bool get isEmpty => sent == 0 && bytes == 0;
}
