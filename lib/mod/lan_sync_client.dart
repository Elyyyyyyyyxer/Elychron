import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/lan_sync_merge.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/data_backup.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:get/get.dart';

/// ===== 局域网同步的**客户端**（去连另一台设备的 Elychron）=====
///
/// 用户口径（2026-09-19）：「手机连接的是电脑端」——
/// 也就是手机上打开「局域网同步 → 连接另一台设备」，填电脑上显示的地址与配对码，
/// 之后就能拉取/推送。桌面端当服务器（键盘在电脑这边，配对码和地址也更好念）。
///
/// 协议就是服务器已有的那三个端点（见 LanSyncServer）：
/// - «POST /pair»   用 6 位配对码换一个会话 token
/// - «GET  /bundle» 拉对方整份数据（带回本机合并）
/// - «POST /bundle» 把本机整份数据推给对方（对方合并）
/// 双向同步 = 先推后拉（推过去的对方会合并，再拉回来就是两边都有的结果）。
///
/// 只处理"两台设备互相认识"这件事，配对信息（地址 + token）存 optionsBox，
/// 下次打开不用重新输码。
class LanSyncClient {
  LanSyncClient._();

  static final LanSyncClient instance = LanSyncClient._();

  static const String _kAddressKey = 'lanSyncPeerAddress';
  static const String _kTokenKey = 'lanSyncPeerToken';

  String? _address;
  String? _token;

  /// 最近一次同步的时间与结果摘要（界面展示用）
  DateTime? lastSyncAt;
  String lastSyncSummary = '';
  String lastSyncDeviceId = '';

  /// 最近一次失败的原因（界面展示用）
  String? lastError;

  bool get isPaired =>
      (_token?.isNotEmpty ?? false) && (_address?.isNotEmpty ?? false);
  String get address => _address ?? '';

  DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  /// 从库里读回上次的配对信息
  void load() {
    try {
      final box = _db?.optionsBox;
      final savedAddress = box?.get(_kAddressKey);
      final savedToken = box?.get(_kTokenKey);
      if (savedAddress is String && savedAddress.isNotEmpty)
        _address = savedAddress;
      if (savedToken is String && savedToken.isNotEmpty) _token = savedToken;
    } catch (_) {
      // 读不出来就当没配对过
    }
  }

  Future<void> _persist() async {
    try {
      final box = _db?.optionsBox;
      if (_address != null) await box?.put(_kAddressKey, _address);
      if (_token != null) await box?.put(_kTokenKey, _token);
    } catch (_) {}
  }

  Future<void> forget() async {
    _address = null;
    _token = null;
    try {
      final box = _db?.optionsBox;
      await box?.delete(_kAddressKey);
      await box?.delete(_kTokenKey);
    } catch (_) {}
  }

  /// 把用户填的地址整理成可用的形式
  ///
  /// 允许几种写法：«192.168.1.5»、«192.168.1.5:8686»、«http://192.168.1.5:8686»，
  /// 也允许直接粘贴配对码所在的那一整行。缺协议补 http、缺端口补 8686。
  static String normalizeAddress(String input) {
    var text = input.trim();
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r'\s+'), '');
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'http://' + text;
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return '';
    final port = uri.hasPort ? uri.port : 8686;
    return 'http://' + uri.host + ':' + port.toString();
  }

  /// 用配对码换 token
  Future<bool> pair({required String address, required String code}) async {
    lastError = null;
    final base = normalizeAddress(address);
    if (base.isEmpty) {
      lastError = '地址看起来不对，像这样：192.168.31.61:8686';
      return false;
    }
    final cleanCode = code.trim();
    if (cleanCode.length != 6) {
      lastError = '配对码是 6 位数字';
      return false;
    }
    final result =
        await _postJson(base + '/pair', <String, dynamic>{'code': cleanCode});
    if (result == null) return false;
    if (result['ok'] != true) {
      lastError = (result['error'] ?? '配对失败').toString();
      return false;
    }
    final token = (result['token'] ?? '').toString();
    if (token.isEmpty) {
      lastError = '对方没有返回 token';
      return false;
    }
    _address = base;
    _token = token;
    await _persist();
    return true;
  }

  /// 拉取：把对方的整份数据带回来合并
  Future<bool> pull() async {
    lastError = null;
    final raw = await _getBundleRaw();
    if (raw == null) return false;
    final incoming = DataBundle.decode(raw);
    if (incoming == null) {
      lastError = '对方给的不是 Elychron 的数据';
      return false;
    }
    final result = await mergeIncomingBundle(incoming: incoming);
    lastSyncAt = DateTime.now();
    lastSyncSummary = (result['summary'] ?? '').toString();
    lastSyncDeviceId = (result['device'] ?? '').toString();
    return true;
  }

  /// 推送：把本机整份数据发给对方（对方负责合并）
  Future<bool> push() async {
    lastError = null;
    final db = _db;
    if (db == null) {
      lastError = '本地数据库还没准备好';
      return false;
    }
    final taskList = Get.find<RxList<Task>>(tag: 'taskList');
    final bundle = await DataBackup.currentBundle(db, taskList.toList());
    final result = await _postJson(
      address + '/bundle',
      bundle.toJson(),
      token: _token,
    );
    if (result == null) return false;
    if (result['ok'] != true) {
      lastError = (result['error'] ?? '推送失败').toString();
      return false;
    }
    lastSyncAt = DateTime.now();
    lastSyncSummary = (result['summary'] ?? '').toString();
    lastSyncDeviceId = (result['device'] ?? '').toString();
    return true;
  }

  /// 双向同步：先推后拉（两边于是都有彼此的改动）
  Future<bool> syncBothWays() async {
    if (!isPaired) {
      lastError = '还没连上对方设备';
      return false;
    }
    if (!await push()) return false;
    return pull();
  }

  // ------------------------------------------------------------- HTTP

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..userAgent = 'Elychron-LanSync';

  /// 拉取对方的整份数据，返回**原始 JSON 文本**（DataBundle.decode 吃字符串）
  Future<String?> _getBundleRaw() async {
    if (!isPaired) {
      lastError = '还没连上对方设备';
      return null;
    }
    final client = _client();
    try {
      final request = await client.getUrl(Uri.parse(address + '/bundle'));
      request.headers.set('X-Lan-Token', _token!);
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        lastError = _explain(response.statusCode, text);
        return null;
      }
      return text;
    } on Object catch (error) {
      lastError = _explainNetwork(error);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _postJson(
    String url,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final client = _client();
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      if (token != null) request.headers.set('X-Lan-Token', token);
      request.add(utf8.encode(jsonEncode(body)));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        lastError = _explain(response.statusCode, text);
        return null;
      }
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on Object catch (error) {
      lastError = _explainNetwork(error);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 把网络的报错翻译成人话（用户看不懂 SocketException）
  String _explainNetwork(Object error) {
    final text = error.toString();
    if (text.contains('Connection refused') || text.contains('errno = 61')) {
      return '连不上：对方没开局域网同步，或者端口不对';
    }
    if (text.contains('timed out') || text.contains('TimeoutException')) {
      return '超时：两台设备不在同一个 Wi-Fi 下？';
    }
    if (text.contains('Failed host lookup')) {
      return '找不到这个地址，检查一下 IP';
    }
    return '网络出错：' + text;
  }

  String _explain(int status, String body) {
    if (status == 401) return '配对已失效，请重新输入配对码';
    if (status == 403) return '对方只允许局域网访问（或者配对码过期了）';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {}
    return '对方返回 HTTP ' + status.toString();
  }
}
