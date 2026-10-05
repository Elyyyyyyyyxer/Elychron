import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// ===== 通知去重：用文件，不用加密存储（2026-09-29）=====
///
/// 用户反馈：「一天会给我推送很多次那个通知，然后我本来应该有的消息提醒就没有了」。
///
/// 原因之一就在这套"这条发过了"的状态存在哪：
/// 通知是在 **后台 isolate** 里发的（WorkManager 每 15 分钟跑一次，一天最多 96 次），
/// 而去重状态原来存在 `FlutterSecureStorage` 里 —— 加密存储要过 Keystore，
/// 后台 isolate 里取不到密钥时它**返回 null 而不是报错**。
/// 于是记录凭空消失：同一条通知每 15 分钟重发一次，
/// 而真正该来的提醒会被系统的防骚扰机制连坐压掉（用户说的"消息提醒没有了"）。
///
/// 所以换成普通文件，和 `RefreshCoordinationStore`（刷新锁）同一套思路：
/// 不管哪个 isolate、哪个进程，读到的都是同一份。
///
/// 它是**最后一道闸**：即使前面所有状态都丢了，同样的内容
/// 在窗口期内也不会重复发出去（见 [sentRecently]）。
class NotificationDedup {
  NotificationDedup._();

  /// 落盘位置解析一次就记住（每个 isolate 各记各的，互不影响）。
  static Directory? _resolvedDirectory;

  /// 2026-10-01：**不能再放临时目录**。
  ///
  /// 原来放在 Directory.systemTemp（手机上是 App 私有缓存，桌面端是临时目录），
  /// 还注释说"系统清掉它顶多多发一次"。用户反馈「始终时不时给我推
  /// '成绩推送已开启'」之后回头看，这个"顶多多发一次"本身就是骚扰：
  /// 缓存被清、覆盖安装之后，"说过了"的记录跟着一起蒸发，
  /// 那条本来一辈子只说一次的开场白就又复活一遍。
  ///
  /// 现在优先放进 App 自己的支持目录（getApplicationSupportDirectory，
  /// 手机上是 files 目录，覆盖安装、清缓存都带不走）；后台 isolate 里
  /// 拿不到插件时退回临时目录 —— 那时候功能不受影响，只是少一道闸。
  static Future<Directory> resolveDirectory() async {
    final cached = _resolvedDirectory;
    if (cached != null) return cached;
    Directory? resolved;
    try {
      final base = await getApplicationSupportDirectory();
      resolved =
          Directory('${base.path}${Platform.pathSeparator}celechron_notify');
      await resolved.create(recursive: true);
    } on Object {
      resolved = null;
    }
    resolved ??= Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}celechron_notify');
    _resolvedDirectory = resolved;
    return resolved;
  }

  static Future<File> fileFor(String key) async {
    final directory = await resolveDirectory();
    return File('${directory.path}${Platform.pathSeparator}$key.json');
  }

  /// 这个 key 上次记了什么（读不到、读坏了都返回 null）
  static Future<Map<String, dynamic>?> read(String key) async {
    try {
      final file = await fileFor(key);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on Object {
      return null;
    }
  }

  static Future<void> write(String key, Map<String, dynamic> value) async {
    try {
      final directory = await resolveDirectory();
      await directory.create(recursive: true);
      final file = await fileFor(key);
      await file.writeAsString(jsonEncode(value), flush: true);
    } on Object {
      // 落盘失败只意味着"下次可能多发一次"，不该阻断通知本身
    }
  }

  /// [fingerprint] 在 [within] 之内已经发过吗
  static Future<bool> sentRecently(
    String key,
    String fingerprint,
    Duration within, {
    DateTime? now,
  }) async {
    final record = await read(key);
    if (record == null) return false;
    if (record['fingerprint'] != fingerprint) return false;
    final at = DateTime.tryParse(record['at']?.toString() ?? '');
    if (at == null) return false;
    final elapsed = (now ?? DateTime.now()).difference(at);
    // 时钟被往后调过（elapsed 为负）也当成"刚发过"，宁可少发一次
    return elapsed < within;
  }

  /// 这个指纹**发过吗**（不管多久以前）。用于"一辈子只说一次"的开场白。
  static Future<bool> everSent(String key, String fingerprint) async {
    final record = await read(key);
    return record != null && record['fingerprint'] == fingerprint;
  }

  static Future<void> markSent(String key, String fingerprint,
          {DateTime? now}) =>
      write(key, <String, dynamic>{
        'fingerprint': fingerprint,
        'at': (now ?? DateTime.now()).toIso8601String(),
      });
}
