import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/pta_spider.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/todo.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:get/get.dart';

/// ===== PTA 作业：配置 / 缓存 / 并进 scholar.todos（2026-10-01）=====
///
/// 用户要求：「PTA 作业与学在浙大作业同等看待 …… 只需要把作业自动作为待办就行」。
///
/// 所以这里**不新增数据模型、也不动 Hive 结构**：PTA 的作业就是一堆 Todo
/// （和学在浙大同一个模型），最终并进 scholar.todos ——
/// 于是作业卡片、作业自动进待办、提醒、通知、跨设备同步**全部白拿**。
///
/// 三个必须处理的坑：
/// 1. 教务/学在浙大每次刷新会把 scholar.todos **整体替换**，所以这里挂一个监听
///    （和 homework_tasks.dart 同一个思路），每次变化后把自己那几条并回去；
/// 2. cookie 会过期 —— **过期时保留上一次的作业**，绝不让用户已经建好的待办消失；
/// 3. 浏览器登录那条路（学号/手机号+验证码）走不通（实测 studentUserLogin=false），
///    所以认证就是粘贴 PTASession，失效了提示重贴。
class PtaHomework {
  PtaHomework._();

  static const String _cacheKey = 'pta_todos';
  static const String _versionKey = 'ptaParseVersion';
  static const Duration _cacheTtl = Duration(minutes: 30);

  /// 解析/筛选规则一变就要 bump 这个版本号。
  ///
  /// 2026-10-01 v2：开始跳过当堂实验/上机（用户：「那种类型的显然不能成为
  /// 作业待办」）。不 bump 的话，旧缓存里那条当堂实验会被当成"上次的结果"
  /// 继续用 —— 装上新版本也看不到修复。
  static const String _parseVersion = 'v2';

  /// 上一次成功拉到的 PTA 作业（内存 + 缓存各一份）
  static List<Todo> _lastGood = <Todo>[];
  static bool _merging = false;
  static bool _fetching = false;

  static DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  static Rx<Scholar>? get _scholar {
    try {
      return Get.find<Rx<Scholar>>(tag: 'scholar');
    } catch (_) {
      return null;
    }
  }

  // ================= 配置（存在 optionsBox，不动 Hive adapter）=================

  static bool get enabled => _db?.getPtaEnabled() ?? false;

  static Future<void> setEnabled(bool value) async {
    await _db?.setPtaEnabled(value);
    await _mirror(enabled: value);
  }

  static String get cookie => _db?.getPtaCookie() ?? '';

  static Future<void> setCookie(String value) async {
    final trimmed = value.trim();
    await _db?.setPtaCookie(trimmed);
    await _mirror(cookie: trimmed);
  }

  static String get lastResult => _db?.getPtaLastResult() ?? '';

  static String get lastSyncAt => _db?.getPtaLastSyncAt() ?? '';

  static bool get configured => enabled && cookie.isNotEmpty;

  /// 当堂实验 / 上机要不要也算作业（默认不算）
  static bool get includeInClass => _db?.getPtaIncludeInClass() ?? false;

  static Future<void> setIncludeInClass(bool value) async {
    await _db?.setPtaIncludeInClass(value);
    await _mirror(includeInClass: value);
  }

  /// 打码后的 cookie（设置页显示用，绝不整串显示）
  static String get maskedCookie {
    final value = cookie;
    if (value.isEmpty) return '（还没填）';
    if (value.length <= 6) return '…';
    return value.substring(0, 4) + '……' + value.substring(value.length - 2);
  }

  // ================= 后台 isolate 的通道 =================
  //
  // 后台任务（WorkManager）跑在**另一个 isolate** 里，那里没有 GetX、也没有 Hive：
  // 它只能读密钥库、读写普通文件。所以：
  //   1) 前台保存设置时，把「开没开 / cookie / 当堂算不算」**镜像一份进密钥库**，
  //      后台照着它自己拉一遍 PTA（这样后台那条「作业截止提醒」也能覆盖 PTA 作业）；
  //   2) 后台把结果写进**文件**，前台启动时先看文件有没有更新的 —— 文件是两个
  //      isolate 之间唯一稳的通道（和 NotificationDedup 同一个思路）。
  static const String _fileName = 'elychron_pta_todos.json';

  static Future<void> _mirror({String? cookie, bool? enabled, bool? includeInClass}) async {
    const storage = FlutterSecureStorage();
    try {
      if (cookie != null) {
        await storage.write(
            key: 'ptaCookie', value: cookie, iOptions: secureStorageIOSOptions);
      }
      if (enabled != null) {
        await storage.write(
            key: 'ptaEnabled',
            value: enabled ? 'true' : 'false',
            iOptions: secureStorageIOSOptions);
      }
      if (includeInClass != null) {
        await storage.write(
            key: 'ptaIncludeInClass',
            value: includeInClass ? 'true' : 'false',
            iOptions: secureStorageIOSOptions);
      }
    } on Object {
      // 密钥库偶尔会闹脾气（见 notification_dedup 的注释）：镜像失败只影响后台，
      // 前台照常能用。
    }
  }

  static Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(dir.path + Platform.pathSeparator + _fileName);
  }

  /// 后台 isolate 调它：把拉到的作业写进文件缓存（后台没有 Hive，只写文件）
  static Future<void> cacheFromBackground(List<Todo> todos) => _writeCache(todos);

  static Future<void> _writeCache(List<Todo> todos) async {
    await _db?.setCachedWebPage(
        _cacheKey, jsonEncode(todos.map((todo) => todo.toJson()).toList()));
    try {
      final file = await _cacheFile();
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'at': DateTime.now().toIso8601String(),
          'todos': todos.map((todo) => todo.toJson()).toList(),
        }),
        flush: true,
      );
    } on Object {
      // 写不了文件就算了（前台还有 Hive 那份）
    }
  }

  /// 文件缓存比 Hive 那份新就用文件（后台可能在 App 没打开时拉过一回）
  static Future<void> _adoptFileCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final at = DateTime.tryParse(decoded['at']?.toString() ?? '');
      if (at == null) return;
      final stamp = DateTime.tryParse(lastSyncAt);
      if (stamp != null && !at.isAfter(stamp)) return;
      final rawTodos = decoded['todos'];
      if (rawTodos is! List) return;
      final todos = rawTodos
          .whereType<Map>()
          .map((item) => Todo.fromJson(Map<String, dynamic>.from(item)))
          .where((todo) => todo.id.isNotEmpty)
          .toList();
      _lastGood = todos;
      await _db?.setPtaLastSyncAt(at.toIso8601String());
      await _db?.setPtaLastResult('已同步 ' + todos.length.toString() + ' 条 PTA 作业');
    } on Object {
      // 读坏了当作没有
    }
  }

  // ================= 合并（纯函数，可单测）=================

  /// 把 PTA 作业并进当前作业列表：**只换 pta: 前缀的那些条目**，
  /// 教务/学在浙大的条目原样保留、顺序也保持。
  static List<Todo> mergeTodos(List<Todo> current, List<Todo> ptaTodos) {
    final others = current.where((todo) => !todo.id.startsWith('pta:')).toList();
    return <Todo>[...others, ...ptaTodos];
  }

  static String _fingerprint(Iterable<Todo> todos) {
    final keys = todos
        .map((todo) => todo.id + '|' + (todo.endTime?.toIso8601String() ?? ''))
        .toList()
      ..sort();
    return keys.join(',');
  }

  /// 把最近一次的结果并回 scholar.todos（幂等；没有变化就什么都不做，免得监听自激）
  static void _apply() {
    final scholar = _scholar;
    if (scholar == null || _merging) return;
    // 本机没开 PTA、也没有本地缓存时什么都别做：那些 pta: 条目可能是
    // **另一台设备同步过来的**，删掉等于把别人的作业抹掉。
    if (!enabled && _lastGood.isEmpty) return;
    final current = scholar.value.todos;
    final currentPta =
        current.where((todo) => todo.id.startsWith('pta:')).toList();
    if (_fingerprint(currentPta) == _fingerprint(_lastGood)) return;

    _merging = true;
    try {
      scholar.value.todos = mergeTodos(current, _lastGood);
      scholar.refresh();
    } finally {
      _merging = false;
    }
  }

  // ================= 生命周期 =================

  /// 规则升级：丢掉旧版本的缓存与时间戳，逼这一次真的去拉一份新数据
  static Future<void> _migrateIfNeeded() async {
    final db = _db;
    if (db == null) return;
    if (db.getCachedWebPage(_versionKey) == _parseVersion) return;
    await db.removeCachedWebPage(_cacheKey);
    await db.setPtaLastSyncAt('');
    await db.setPtaLastResult('');
    await db.setCachedWebPage(_versionKey, _parseVersion);
    try {
      final file = await _cacheFile();
      if (await file.exists()) await file.delete();
    } on Object {
      // 删不掉也没关系：文件里那份会被当成"比 Hive 旧"
    }
  }

  /// 启动：升级检查 → 读缓存 → 先显示上次的作业 → 挂监听
  static Future<void> restore() async {
    await _migrateIfNeeded();
    await _adoptFileCache();
    final raw = _db?.getCachedWebPage(_cacheKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _lastGood = decoded
              .whereType<Map>()
              .map((item) => Todo.fromJson(Map<String, dynamic>.from(item)))
              .where((todo) => todo.id.isNotEmpty)
              .toList();
        }
      } on Object {
        // 缓存读坏了就当作没有，不影响启动
      }
    }
    _apply();
  }

  /// 每次 scholar 变化后把 PTA 作业并回去（整体替换会冲掉它们）
  static void startMergeListener() {
    final scholar = _scholar;
    if (scholar == null) return;
    scholar.listen((_) => _apply());
    _apply();
  }

  /// 拉一次。返回一句人话结果（设置页显示、也写进 lastResult）
  static Future<String> refresh({bool force = false}) async {
    if (!enabled) return 'PTA 还没开启';
    if (cookie.isEmpty) return '还没填 PTASession';
    if (_fetching) return '正在同步…';
    if (!force && _freshEnough()) {
      return lastResult.isEmpty ? '刚同步过' : lastResult;
    }

    _fetching = true;
    final spider = PtaSpider(cookie: cookie);
    try {
      final parsed = await spider.fetchActive(includeInClass: includeInClass);
      final todos = parsed.todos;
      _lastGood = todos;
      await _writeCache(todos);
      final stamp = DateTime.now().toIso8601String();
      await _db?.setPtaLastSyncAt(stamp);
      var result = '已同步 ' + todos.length.toString() + ' 条 PTA 作业';
      if (parsed.skippedInClass > 0) {
        result = result +
            '（跳过 ' +
            parsed.skippedInClass.toString() +
            ' 条当堂实验 / 上机）';
      }
      await _db?.setPtaLastResult(result);
      _apply();
      DiagnosticLogService.instance.record(
        module: 'PTA',
        operation: 'refresh',
        message: result,
      );
      return result;
    } on PtaAuthExpiredException catch (error) {
      // cookie 过期：**保留上一次的作业**，只把话说明白
      final result =
          error.message + '（保留上一次的 ' + _lastGood.length.toString() + ' 条）';
      await _db?.setPtaLastResult(result);
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: 'PTA',
        operation: 'authExpired',
        message: result,
      );
      return result;
    } on Object catch (error) {
      final result = 'PTA 同步失败：' +
          error.toString() +
          '（保留上一次的 ' +
          _lastGood.length.toString() +
          ' 条）';
      await _db?.setPtaLastResult(result);
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.warning,
        module: 'PTA',
        operation: 'refreshFailed',
        message: result,
        error: error,
      );
      return result;
    } finally {
      spider.close();
      _fetching = false;
    }
  }

  /// 测试连接：只验 cookie（不写作业）
  static Future<String> testConnection() async {
    if (cookie.isEmpty) return '还没填 PTASession';
    final spider = PtaSpider(cookie: cookie);
    try {
      final nickname = await spider.whoAmI();
      if (nickname.isEmpty) return 'cookie 是通的，但没读到用户信息';
      return '连接成功：' + nickname;
    } on Object catch (error) {
      return error.toString();
    } finally {
      spider.close();
    }
  }

  static bool _freshEnough() {
    final raw = lastSyncAt;
    if (raw.isEmpty) return false;
    final at = DateTime.tryParse(raw);
    if (at == null) return false;
    return DateTime.now().difference(at) < _cacheTtl;
  }

  /// 清除 cookie（退出 PTA）
  static Future<void> clearCookie() async {
    await _db?.setPtaCookie('');
    await _mirror(cookie: '');
    _lastGood = <Todo>[];
    await _db?.removeCachedWebPage(_cacheKey);
    final result = '已清除 PTA 登录信息';
    await _db?.setPtaLastResult(result);
    _apply();
  }
}
