import 'dart:async';
import 'dart:convert';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/pta_spider.dart';
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
  static const Duration _cacheTtl = Duration(minutes: 30);

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
  }

  static String get cookie => _db?.getPtaCookie() ?? '';

  static Future<void> setCookie(String value) async {
    await _db?.setPtaCookie(value.trim());
  }

  static String get lastResult => _db?.getPtaLastResult() ?? '';

  static String get lastSyncAt => _db?.getPtaLastSyncAt() ?? '';

  static bool get configured => enabled && cookie.isNotEmpty;

  /// 打码后的 cookie（设置页显示用，绝不整串显示）
  static String get maskedCookie {
    final value = cookie;
    if (value.isEmpty) return '（还没填）';
    if (value.length <= 6) return '…';
    return value.substring(0, 4) + '……' + value.substring(value.length - 2);
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

  /// 启动：读缓存 → 先显示上次的作业 → 挂监听
  static Future<void> restore() async {
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
      final todos = await spider.fetchActive();
      _lastGood = todos;
      await _db?.setCachedWebPage(
          _cacheKey, jsonEncode(todos.map((todo) => todo.toJson()).toList()));
      final stamp = DateTime.now().toIso8601String();
      await _db?.setPtaLastSyncAt(stamp);
      final result = '已同步 ' + todos.length.toString() + ' 条 PTA 作业';
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
    _lastGood = <Todo>[];
    await _db?.removeCachedWebPage(_cacheKey);
    final result = '已清除 PTA 登录信息';
    await _db?.setPtaLastResult(result);
    _apply();
  }
}
