import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/database_mod.dart';
import 'package:celechron/mod/lan_panel.dart';
import 'package:celechron/mod/lan_sync_merge.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/data_backup.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

/// ============ 局域网直连同步（本机当服务器）============
///
/// 设计目标：**不依赖任何账号**。同一 Wi-Fi 下，电脑/平板用浏览器打开面板
/// 就能看待办、打钩、新建，也能导出/导入整份数据。
///
/// - 只用 `dart:io` 的 `HttpServer`，不引入任何新依赖
/// - 默认关闭，必须在设置里手动开启；仅绑局域网，不做端口转发
/// - 配对码 + 一次性 token 两道门，防止同网段的其他设备直接读到数据
/// - 同步逻辑完全复用 `DataBundle` + `DataMerge`（按 uid/updatedAt/墓碑合并）
class LanSyncServer {
  LanSyncServer._();

  static final LanSyncServer instance = LanSyncServer._();

  /// 依次尝试的端口，第一个没被占用就用它
  static const List<int> candidatePorts = [8686, 8687, 8688, 8689];

  HttpServer? _server;
  String _code = '';
  int _port = candidatePorts.first;
  String _ip = '127.0.0.1';
  final Set<String> _tokens = <String>{};
  final Random _random = Random.secure();

  /// 启动失败时的原因（没绑上端口、没有局域网 IP 等）
  String? lastError;

  /// 最近一次同步的时间与结果摘要（用于界面展示）
  DateTime? lastSyncAt;

  /// 最近一次把本机数据交出去（面板拉取）的时刻。
  ///
  /// 用途：判断对方推回来的那份是不是比我们给出去的更新， 设置项整组取舍要用
  /// （见 DataMerge.merge 的 localExportedAt）。从没拉过（null）就按对方更新处理，
  /// 也就是首次同步以对方为准。
  DateTime? lastPullAt;

  /// 最近一次推送给我们的数据来自哪台设备（面板上显示最后同步来自 X）
  String lastSyncDeviceId = '';
  String lastSyncSummary = '';

  bool get isRunning => _server != null;
  String get code => _code;
  int get port => _port;

  /// 给电脑浏览器输入的地址；没启动时为 null
  String? get url => isRunning ? 'http://$_ip:$_port' : null;

  Future<void> start() async {
    if (isRunning) return;
    lastError = null;

    _ip = await _findLanIp();
    if (_ip == '127.0.0.1') {
      lastError = '没有找到局域网地址，请先连接 Wi-Fi';
      return;
    }

    HttpServer? server;
    var usedPort = candidatePorts.first;
    final failures = <String>[];
    for (final candidate in candidatePorts) {
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          candidate,
          shared: false,
        );
        usedPort = candidate;
        break;
      } on SocketException {
        failures.add('$candidate');
      }
    }
    if (server == null) {
      lastError = '端口被占用（${failures.join('、')}）';
      return;
    }

    _server = server;
    _port = usedPort;
    _code = (100000 + _random.nextInt(899999)).toString();
    _tokens.clear();

    _server!.listen(
      (request) {
        _handle(request).catchError((Object error) async {
          // 单个请求出错不能拖垮整个服务
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } catch (_) {}
        });
      },
      onError: (Object error) {
        lastError = '服务异常：$error';
        stop();
      },
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _tokens.clear();
    _code = '';
    try {
      await server?.close(force: true);
    } catch (_) {}
  }

  // ------------------------------------------------------------- 路由

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      response.headers.set('Access-Control-Allow-Origin', '*');
      response.headers
          .set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      response.headers
          .set('Access-Control-Allow-Headers', 'Content-Type, X-Lan-Token');
      await response.close();
      return;
    }

    // 只服务同网段的设备：外网/公网地址一律拒绝
    final remote = request.connectionInfo?.remoteAddress;
    if (remote != null && !_isPrivate(remote)) {
      return _text(response, HttpStatus.forbidden, '仅限局域网访问');
    }

    final path = request.uri.path;
    try {
      if (request.method == 'GET' && (path == '/' || path == '/index.html')) {
        return _html(response, lanPanelHtml);
      }
      // 浏览器会自动请求 favicon；明确返回空响应，避免无意义的 404
      // 干扰网页端控制台和连接诊断。
      if (request.method == 'GET' && path == '/favicon.ico') {
        response.statusCode = HttpStatus.noContent;
        response.headers.set('Cache-Control', 'no-store');
        await response.close();
        return;
      }
      if (request.method == 'POST' && path == '/pair') {
        return await _pair(request);
      }
      if (path == '/bundle') {
        if (!_authorized(request)) {
          return _json(response, HttpStatus.unauthorized,
              {'ok': false, 'error': '未配对或配对已失效，请重新输入配对码'});
        }
        if (request.method == 'GET') return await _sendBundle(response);
        if (request.method == 'POST') return await _receiveBundle(request);
      }
      // 附件本体（2026-09-19）：同步协议里只有 name/path/size，二进制得单独取
      if (path == '/file' && request.method == 'GET') {
        if (!_authorized(request)) {
          return _json(response, HttpStatus.unauthorized,
              {'ok': false, 'error': '未配对或配对已失效，请重新输入配对码'});
        }
        return await _sendFile(
            response, request.uri.queryParameters['path'] ?? '');
      }
      if (path == '/meta' && request.method == 'GET') {
        if (!_authorized(request)) {
          return _json(response, HttpStatus.unauthorized,
              {'ok': false, 'error': '未配对或配对已失效，请重新输入配对码'});
        }
        final db = Get.find<DatabaseHelper>(tag: 'db');
        return _json(response, HttpStatus.ok, {
          'ok': true,
          'device': await db.getDeviceId(),
          'lastSyncAt': lastSyncAt?.toIso8601String(),
          'lastSyncDeviceId': lastSyncDeviceId,
          'reminderMode': db.getReminderMode(),
          'reminderLeadMinutes': db.getReminderLeadMinutes(),
        });
      }
      return _text(response, HttpStatus.notFound, 'not found');
    } on FormatException {
      // 请求体不是合法 JSON：明确回 400，而不是含混的 500
      return _json(response, HttpStatus.badRequest,
          {'ok': false, 'error': '请求体不是合法 JSON'});
    } catch (error) {
      return _json(response, HttpStatus.internalServerError,
          {'ok': false, 'error': '$error'});
    }
  }

  /// 用 App 页面上显示的 6 位配对码换取一个会话 token
  Future<void> _pair(HttpRequest request) async {
    final body = await _readBody(request);
    final input = (body['code'] ?? '').toString().trim();
    if (input.isEmpty || input != _code) {
      return _json(request.response, HttpStatus.forbidden,
          {'ok': false, 'error': '配对码不对'});
    }
    final token = List<int>.generate(16, (_) => _random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _tokens.add(token);
    return _json(request.response, HttpStatus.ok, {'ok': true, 'token': token});
  }

  bool _authorized(HttpRequest request) {
    // Token 只允许通过请求头传递，避免出现在浏览器历史、代理日志和 Referer 中。
    final token = request.headers.value('X-Lan-Token');
    return token != null && token.isNotEmpty && _tokens.contains(token);
  }

  /// 拉取：把本机的整份数据交给浏览器端
  Future<void> _sendBundle(HttpResponse response) async {
    final db = Get.find<DatabaseHelper>(tag: 'db');
    final bundle = await DataBackup.currentBundle(db, _tasks());
    lastPullAt = DateTime.now();
    return _json(response, HttpStatus.ok, bundle.toJson());
  }

  /// 推送：把浏览器/另一台设备的改动合并回本机
  ///
  /// 合并本身走公共实现（lib/mod/lan_sync_merge.dart），不在这里另写一份。
  Future<void> _receiveBundle(HttpRequest request) async {
    final body = await _readBodyRaw(request);
    final incoming = DataBundle.decode(body);
    if (incoming == null) {
      return _json(request.response, HttpStatus.badRequest,
          {'ok': false, 'error': '数据格式不对，不是 Elychron 的备份'});
    }

    final result = await mergeIncomingBundle(
      incoming: incoming,
      localExportedAt: lastPullAt,
    );

    lastSyncAt = DateTime.now();
    lastSyncSummary = (result['summary'] ?? '').toString();
    lastSyncDeviceId = (result['device'] ?? '').toString();
    return _json(request.response, HttpStatus.ok, result);
  }
  // ------------------------------------------------------------- 工具

  List<Task> _tasks() => Get.find<RxList<Task>>(tag: 'taskList').toList();

  Future<Map<String, dynamic>> _readBody(HttpRequest request) async {
    final text = await _readBodyRaw(request);
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  Future<String> _readBodyRaw(HttpRequest request) {
    return utf8.decoder.bind(request).join();
  }

  Future<void> _json(
      HttpResponse response, int status, Map<String, dynamic> data) async {
    response.statusCode = status;
    response.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers
        .set('Access-Control-Allow-Headers', 'Content-Type, X-Lan-Token');
    response.write(jsonEncode(data));
    await response.close();
  }

  /// 送一个附件文件（附件本体同步用）
  ///
  /// ⚠️ 安全：path 是**对方给的**，不设防就等于把整台机器的读文件权限交出去。
  /// 所以只允许取"应用自己文档目录里"的文件（附件都复制在那下面），
  /// 解析后的绝对路径必须以文档目录开头，否则一律 403。
  Future<void> _sendFile(HttpResponse response, String rawPath) async {
    final path = rawPath.isEmpty ? '' : Uri.decodeComponent(rawPath);
    if (path.isEmpty) {
      return _json(
          response, HttpStatus.badRequest, {'ok': false, 'error': '缺少 path'});
    }
    try {
      final docs = (await getApplicationDocumentsDirectory()).absolute.path;
      final resolved = File(path).absolute.path;
      if (!resolved.startsWith(docs)) {
        return _json(response, HttpStatus.forbidden,
            {'ok': false, 'error': '只能取应用自己目录里的文件'});
      }
      final file = File(resolved);
      if (!await file.exists()) {
        return _json(
            response, HttpStatus.notFound, {'ok': false, 'error': '对方没有这个文件'});
      }
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.binary;
      response.headers.contentLength = await file.length();
      response.headers.set('Cache-Control', 'no-store');
      await response.addStream(file.openRead());
      await response.close();
    } catch (error) {
      return _json(response, HttpStatus.internalServerError,
          {'ok': false, 'error': '$error'});
    }
  }

  Future<void> _text(HttpResponse response, int status, String text) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.text;
    response.headers.set('Cache-Control', 'no-store');
    response.write(text);
    await response.close();
  }

  Future<void> _html(HttpResponse response, String html) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType =
        ContentType('text', 'html', charset: 'utf-8');
    response.headers.set('Cache-Control', 'no-store');
    response.write(html);
    await response.close();
  }

  /// 只认回环 / 链路本地 / RFC1918 私网地址
  static bool _isPrivate(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return true;
    final raw = address.rawAddress;
    if (raw.length == 4) {
      final a = raw[0];
      final b = raw[1];
      if (a == 10) return true;
      if (a == 192 && b == 168) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      return false;
    }
    // IPv6 唯一本地地址 fc00::/7
    return (raw[0] & 0xfe) == 0xfc;
  }

  /// 找本机在局域网里的 IPv4 地址（优先 192.168 / 10 / 172 段）
  static Future<String> _findLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final candidates = <String>[];
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (_isPrivate(address)) candidates.add(address.address);
        }
      }
      if (candidates.isEmpty) return '127.0.0.1';
      // 家用/校园 Wi-Fi 最常见的是 192.168 段，优先它
      candidates.sort((a, b) {
        int rank(String ip) {
          if (ip.startsWith('192.168.')) return 0;
          if (ip.startsWith('10.')) return 1;
          return 2;
        }

        return rank(a).compareTo(rank(b));
      });
      return candidates.first;
    } catch (_) {
      return '127.0.0.1';
    }
  }
}
