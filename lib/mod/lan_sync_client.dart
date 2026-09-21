import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/lan_sync_merge.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/utils/data_backup.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

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

  /// ===== 自动同步（用户要求：每有一次变动就同步一次）=====
  ///
  /// 做法：盯着本机待办列表，一变就**防抖 4 秒**后推给对方；
  /// 另外每 60 秒拉一次对方的改动（否则对方改了这边不会知道）。
  ///
  /// 为什么不怕来回震荡：合并是幂等的（数据没变就什么都不更新），
  /// 所以"拉取触发的变更"再推回去，对方那边不会产生新变更，链条自然停；
  /// 同步进行中收到的变更事件也一律忽略（_syncing），彻底断掉自激。
  static const String _kAutoSyncKey = 'lanSyncAuto';

  bool _autoSync = true;
  bool get autoSyncEnabled => _autoSync;
  Timer? _debounce;
  Timer? _pullTimer;
  StreamSubscription<List<Task>>? _taskSub;
  bool _syncing = false;

  Future<void> setAutoSync(bool value) async {
    _autoSync = value;
    try {
      await _db?.optionsBox.put(_kAutoSyncKey, value);
    } catch (_) {}
    if (value) {
      startAutoSync();
    } else {
      stopAutoSync();
    }
  }

  /// 开始自动同步（没配对、或用户关掉了，就什么都不做）
  void startAutoSync() {
    if (!isPaired || !_autoSync) return;
    final list = _taskListOf();
    if (list != null) {
      _taskSub ??= list.listen((_) {
        if (_syncing) return;
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 4), () {
          if (!isPaired || !_autoSync) return;
          push();
        });
      });
    }
    _pullTimer ??= Timer.periodic(const Duration(seconds: 60), (_) {
      if (!isPaired || !_autoSync || _syncing) return;
      pull();
    });
  }

  void stopAutoSync() {
    _debounce?.cancel();
    _debounce = null;
    _pullTimer?.cancel();
    _pullTimer = null;
    _taskSub?.cancel();
    _taskSub = null;
  }

  RxList<Task>? _taskListOf() {
    try {
      return Get.find<RxList<Task>>(tag: 'taskList');
    } catch (_) {
      return null;
    }
  }

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
      final savedAuto = box?.get(_kAutoSyncKey);
      if (savedAuto is bool) _autoSync = savedAuto;
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
    stopAutoSync();
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
    startAutoSync();
    return true;
  }

  /// 拉取：把对方的整份数据带回来合并
  Future<bool> pull() async {
    if (_syncing) return false;
    _syncing = true;
    try {
      return await _pullInner();
    } finally {
      _syncing = false;
    }
  }

  Future<bool> _pullInner() async {
    lastError = null;
    final raw = await _getBundleRaw();
    if (raw == null) return false;
    final incoming = DataBundle.decode(raw);
    if (incoming == null) {
      lastError = '对方给的不是 Elychron 的数据';
      return false;
    }
    final result = await mergeIncomingBundle(incoming: incoming);
    // 合并完把"对方有、本机没有"的附件文件取回来（附件本体同步）
    final fetched = await _fetchMissingFiles();
    lastSyncAt = DateTime.now();
    final summary = (result['summary'] ?? '').toString();
    lastSyncSummary = fetched > 0 ? '$summary，取回 $fetched 个文件' : summary;
    lastSyncDeviceId = (result['device'] ?? '').toString();
    return true;
  }

  /// 把对方有、本机没有的附件文件取回来
  ///
  /// 为什么需要它：同步协议里附件只有 name/path/size，**二进制不过网** ——
  /// 于是另一台设备上那一行在、点开是空的。这里在每次拉取之后扫一遍
  /// 待办附件与课程挂载的资料，缺哪个就按 path 找对方要（GET /file），
  /// 存进本机的附件目录，并把记录里的 path 改成本机路径。
  ///
  /// 只在"本机确实没有这个文件"时才下载，所以重复同步不会反复传。
  Future<int> _fetchMissingFiles() async {
    final db = _db;
    final list = _taskListOf();
    if (db == null || list == null) return 0;
    Directory? attachDir;
    var fetched = 0;
    var tasksChanged = false;

    Future<String?> grab(String remotePath) async {
      if (remotePath.isEmpty) return null;
      if (await File(remotePath).exists()) return null; // 本机已经有了
      if (attachDir == null) {
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory(docs.path + '/task_attachments');
        if (!await dir.exists()) await dir.create(recursive: true);
        attachDir = dir;
      }
      final dir = attachDir!;
      final name = remotePath.split(RegExp(r'[\\/]')).last;
      final safeName = name.isEmpty ? 'attachment' : name;
      final stamp = DateTime.now().microsecondsSinceEpoch.toString();
      final target = File(dir.path + '/' + stamp + '_' + safeName);
      final raw = await _downloadFile(remotePath);
      if (raw == null) return null;
      await target.writeAsBytes(raw);
      fetched++;
      return target.path;
    }

    // (1) 待办附件
    final tasks = list.toList();
    for (final task in tasks) {
      for (final attachment in task.attachments) {
        final local = await grab(attachment.path);
        if (local != null) {
          attachment.path = local;
          tasksChanged = true;
        }
      }
    }
    if (tasksChanged) {
      await db.setTaskList(list);
      list.refresh();
    }

    // (2) 课程挂载的资料
    for (final entry in db.courseMountBox.toMap().entries) {
      final courseId = entry.key.toString();
      final raw = entry.value;
      if (raw is! Map) continue;
      final attachments = (raw['attachments'] as List?)?.toList();
      if (attachments == null || attachments.isEmpty) continue;
      var changed = false;
      for (final item in attachments) {
        if (item is! Map) continue;
        final local = await grab(item['path']?.toString() ?? '');
        if (local != null) {
          item['path'] = local;
          changed = true;
        }
      }
      if (changed) {
        await db.courseMountBox.put(courseId, <String, dynamic>{
          'attachments': attachments,
          'comments': raw['comments'] ?? const <dynamic>[],
        });
      }
    }
    return fetched;
  }

  /// 从对方下载一个文件（附件本体）
  Future<Uint8List?> _downloadFile(String remotePath) async {
    if (!isPaired) return null;
    final client = _client();
    try {
      final uri = Uri.parse(address + '/file').replace(
        queryParameters: <String, String>{'path': remotePath},
      );
      final request = await client.getUrl(uri);
      request.headers.set('X-Lan-Token', _token!);
      final response =
          await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        lastError = _explain(response.statusCode, '');
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on Object catch (error) {
      lastError = _explainNetwork(error);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 任何一处用户数据变了都调它：防抖后推给对方
  ///
  /// 用户要求「每次操作都会进行一次同步」。原来只盯着待办列表
  /// （见 startAutoSync），专注记录 / 课程挂载 / 标签这些改了不会触发推送，
  /// 要等下一次手动同步或别的操作顺带推。现在这些写库的地方都调这个，口径统一。
  void scheduleSync() {
    if (!isPaired || !_autoSync || _syncing) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () {
      if (!isPaired || !_autoSync) return;
      push();
    });
  }

  /// 推送：把本机整份数据发给对方（对方负责合并）
  Future<bool> push() async {
    if (_syncing) return false;
    _syncing = true;
    try {
      return await _pushInner();
    } finally {
      _syncing = false;
    }
  }

  Future<bool> _pushInner() async {
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
