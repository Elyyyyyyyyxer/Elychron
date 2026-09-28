import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/focus_device.dart';
import 'package:celechron/mod/webdav_client.dart';
import 'package:celechron/mod/webdav_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

/// ===== 全平台同步（W3）：配置存在哪 =====
///
/// 用户要求：「尽可能简化用户操作流程」。所以这个类把"配置"压缩成三样东西：
///   地址 / 用户名 / 密码（应用密码）
/// 其余（目录名、文件名、设备号、上次同步到哪）**全部由程序自己管**，用户永远不用填。
///
/// 存法遵循项目既有约定：
/// - 地址、用户名、开关、上次同步结果 → optionsBox（本来就是给魔改新增状态用的）；
/// - 密码 → 系统密钥库（与 AI key 同一套设施），**不写进数据库、不跟着导出**。
///
/// ⚠️ 一个 Hive 字段都不动（用户反复强调过：加字段忘了改 adapter 会搞崩数据）。
class WebDavConfig {
  WebDavConfig._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _kUrl = 'webdav_url';
  static const String _kUsername = 'webdav_username';
  static const String _kProvider = 'webdav_provider';
  static const String _kEnabled = 'webdav_enabled';
  static const String _kLastSyncAt = 'webdav_last_sync_at';
  static const String _kLastSummary = 'webdav_last_summary';
  static const String _kLastFailed = 'webdav_last_failed';
  static const String _kPasswordSecret = 'webdav_password';

  // ===== W4：附件本体 =====
  //
  // 附件二进制默认不过网，否则"第一次同步"会把用户几年的照片全传上来。
  // 但元数据（name/path/size）一直会同步，所以另一台设备上那一行在、点开是空的；
  // 打开这个开关才把文件本体也搬过去。
  static const String _kFileSync = 'webdav_file_sync';
  static const String _kTrafficMonth = 'webdav_traffic_month';
  static const String _kTrafficUp = 'webdav_traffic_upload';
  static const String _kTrafficDown = 'webdav_traffic_download';
  static const String _kFileIndex = 'webdav_file_index';

  /// 本机路径 → 它在网盘上的名字。
  ///
  /// 为什么需要它：从网盘取回来的文件，本机路径是我们自己起的
  /// （`task_attachments/1749xxxx_照片.jpg`）。下次同步如果再按"本机路径"算哈希，
  /// 就会算出一个新名字，把**同一份文件重复传上去**一遍 —— 配额白白跑掉一半。
  /// 记住"这个本地文件是网盘上哪个文件落下来的"，就不会重复传。
  static const String _kFileOrigin = 'webdav_file_origin';

  /// 坚果云免费版：每月上传 1 GB、下载 3 GB。这里留一点余量，
  /// 别把配额跑光 —— 配额用尽是"整个同步都不动了"，比"有些文件没传"严重得多。
  static const int monthlyUploadBudget = 900 * 1024 * 1024;

  /// 单文件上限：超过就不传（界面上如实说明，不默默跳过）
  static const int maxFileBytes = 50 * 1024 * 1024;

  /// 每次改动 bump 一下，界面用它刷新（不把 Rx 依赖带进这个纯工具类）
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool _enabled = false;
  static String _url = '';
  static String _username = '';
  static String _password = '';
  static String _providerName = '';
  static String _lastSummary = '';
  static bool _lastFailed = false;
  static DateTime? _lastSyncAt;
  static bool _loaded = false;
  static bool _fileSync = false;
  static int _uploadedBytes = 0;
  static int _downloadedBytes = 0;
  static String _trafficMonth = '';
  static String _fileIndexRaw = '{}';
  static String _fileOriginRaw = '{}';

  static bool get enabled => _enabled;
  static String get url => _url;
  static String get username => _username;
  static String get providerName => _providerName;
  static String get lastSummary => _lastSummary;
  static bool get lastFailed => _lastFailed;
  static DateTime? get lastSyncAt => _lastSyncAt;
  static bool get loaded => _loaded;

  /// 附件本体要不要也传（默认关：第一次打开就全传会把网盘配额一把打光）
  static bool get fileSyncEnabled => _fileSync;
  static int get uploadedBytesThisMonth => _uploadedBytes;
  static int get downloadedBytesThisMonth => _downloadedBytes;
  static String get fileIndexRaw => _fileIndexRaw;
  static String get fileOriginRaw => _fileOriginRaw;

  /// 本月还剩多少上传额度（界面用它决定要不要变红）
  static int get uploadBudgetLeft {
    final left = monthlyUploadBudget - _uploadedBytes;
    return left < 0 ? 0 : left;
  }

  /// 三样都填了才算配置好（缺一样就同步不了，界面据此判断要不要走向导）
  static bool get isConfigured =>
      _url.isNotEmpty && _username.isNotEmpty && _password.isNotEmpty;

  static DatabaseHelper? get _db {
    try {
      return Get.find<DatabaseHelper>(tag: 'db');
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ 读

  static Future<void> load() async {
    final box = _db?.optionsBox;
    try {
      _url = (box?.get(_kUrl) as String?) ?? '';
      _username = (box?.get(_kUsername) as String?) ?? '';
      _providerName = (box?.get(_kProvider) as String?) ?? '';
      _enabled = (box?.get(_kEnabled) as bool?) ?? false;
      _lastSummary = (box?.get(_kLastSummary) as String?) ?? '';
      _lastFailed = (box?.get(_kLastFailed) as bool?) ?? false;
      final stamp = box?.get(_kLastSyncAt) as String?;
      _lastSyncAt = stamp == null ? null : DateTime.tryParse(stamp);
      _fileSync = (box?.get(_kFileSync) as bool?) ?? false;
      _fileIndexRaw = (box?.get(_kFileIndex) as String?) ?? '{}';
      _fileOriginRaw = (box?.get(_kFileOrigin) as String?) ?? '{}';
      final month = currentMonthKey();
      final storedMonth = (box?.get(_kTrafficMonth) as String?) ?? '';
      if (storedMonth == month) {
        _trafficMonth = storedMonth;
        _uploadedBytes = (box?.get(_kTrafficUp) as int?) ?? 0;
        _downloadedBytes = (box?.get(_kTrafficDown) as int?) ?? 0;
      } else {
        // 跨月了：流量归零（各家免费版的额度都是按月算的）
        _trafficMonth = month;
        _uploadedBytes = 0;
        _downloadedBytes = 0;
        await box?.put(_kTrafficMonth, month);
        await box?.put(_kTrafficUp, 0);
        await box?.put(_kTrafficDown, 0);
      }
    } catch (_) {}
    try {
      _password = await _storage.read(key: _kPasswordSecret) ?? '';
    } catch (_) {
      _password = '';
    }
    _loaded = true;
    revision.value++;
  }

  // ------------------------------------------------------------ 写

  /// 保存（向导走完时调用一次）。用户名会自动 trim —— 从网页复制邮箱
  /// 常常带一个尾空格，那会造成 401，而错误信息完全看不出问题在哪。
  static Future<void> save({
    required String url,
    required String username,
    required String password,
    String providerName = '',
  }) async {
    _url = normalizeUrl(url);
    _username = username.trim();
    _password = password.trim();
    if (providerName.isNotEmpty) _providerName = providerName;
    final box = _db?.optionsBox;
    try {
      await box?.put(_kUrl, _url);
      await box?.put(_kUsername, _username);
      await box?.put(_kProvider, _providerName);
    } catch (_) {}
    try {
      if (_password.isEmpty) {
        await _storage.delete(key: _kPasswordSecret);
      } else {
        await _storage.write(key: _kPasswordSecret, value: _password);
      }
    } catch (_) {}
    revision.value++;
  }

  /// 自检时若用户名被自动转成小写（坚果云那类坑），把改好的写回去，
  /// 下次就不用再试一遍错的了。
  static Future<void> setUsername(String value) async {
    final next = value.trim();
    if (next == _username) return;
    _username = next;
    try {
      await _db?.optionsBox.put(_kUsername, next);
    } catch (_) {}
    revision.value++;
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      await _db?.optionsBox.put(_kEnabled, value);
    } catch (_) {}
    revision.value++;
  }

  /// 记下这次同步的结果（界面要显示"上次同步：…"）
  static Future<void> recordSync(String summary, {bool failed = false}) async {
    _lastSummary = summary;
    _lastFailed = failed;
    _lastSyncAt = DateTime.now();
    final box = _db?.optionsBox;
    try {
      await box?.put(_kLastSummary, summary);
      await box?.put(_kLastFailed, failed);
      await box?.put(_kLastSyncAt, _lastSyncAt!.toIso8601String());
    } catch (_) {}
    revision.value++;
  }

  /// 断开（清掉账号密码与开关；上次同步记录留着，用户回头能看到）
  static Future<void> clear() async {
    _url = '';
    _username = '';
    _password = '';
    _providerName = '';
    _enabled = false;
    final box = _db?.optionsBox;
    try {
      await box?.put(_kUrl, '');
      await box?.put(_kUsername, '');
      await box?.put(_kProvider, '');
      await box?.put(_kEnabled, false);
    } catch (_) {}
    try {
      await _storage.delete(key: _kPasswordSecret);
    } catch (_) {}
    revision.value++;
  }

  // ------------------------------------------------------------ W4 附件

  static Future<void> setFileSyncEnabled(bool value) async {
    _fileSync = value;
    try {
      await _db?.optionsBox.put(_kFileSync, value);
    } catch (_) {}
    revision.value++;
  }

  /// 记一笔流量（跨月自动归零）
  static Future<void> addTraffic({int up = 0, int down = 0}) async {
    if (up == 0 && down == 0) return;
    final month = currentMonthKey();
    if (_trafficMonth != month) {
      _trafficMonth = month;
      _uploadedBytes = 0;
      _downloadedBytes = 0;
    }
    _uploadedBytes += up;
    _downloadedBytes += down;
    final box = _db?.optionsBox;
    try {
      await box?.put(_kTrafficMonth, _trafficMonth);
      await box?.put(_kTrafficUp, _uploadedBytes);
      await box?.put(_kTrafficDown, _downloadedBytes);
    } catch (_) {}
    revision.value++;
  }

  static Future<void> setFileIndexRaw(String raw) async {
    _fileIndexRaw = raw;
    try {
      await _db?.optionsBox.put(_kFileIndex, raw);
    } catch (_) {}
  }

  static Future<void> setFileOriginRaw(String raw) async {
    _fileOriginRaw = raw;
    try {
      await _db?.optionsBox.put(_kFileOrigin, raw);
    } catch (_) {}
  }

  /// 本机设备号（同步时告诉对方这份数据来自哪台设备）
  static String get deviceIdOfThisDevice {
    try {
      return _db?.getDeviceId() ?? 'device';
    } catch (_) {
      return 'device';
    }
  }

  /// '2026-09'：流量按月算（各家免费版都是这么算的）
  static String currentMonthKey([DateTime? now]) {
    final at = now ?? DateTime.now();
    return at.year.toString() + '-' + at.month.toString().padLeft(2, '0');
  }

  // ------------------------------------------------------------ 造对象

  static WebDavClient? buildClient() {
    if (!isConfigured) return null;
    return WebDavClient(
      baseUrl: _url,
      username: _username,
      password: _password,
    );
  }

  static WebDavSync? buildSync() {
    final client = buildClient();
    if (client == null) return null;
    var deviceId = 'device';
    try {
      deviceId = _db?.getDeviceId() ?? 'device';
    } catch (_) {}
    return WebDavSync(
      client,
      deviceId: deviceId,
      deviceName: FocusDevice.current,
    );
  }

  // ------------------------------------------------------------ 纯函数（单测钉着）

  /// 把用户贴进来的地址修成能用的样子。
  ///
  /// 从网页/客服聊天里复制地址，最常见的三种残缺：
  ///   1. 只复制了域名（坚果云官方文档写的就是 dav.jianguoyun.com/dav/）；
  ///   2. 末尾少了那个斜杠；
  ///   3. 前后带空格或引号。
  /// 这三种都会让请求打到"看起来对"的地方然后 401/404，用户完全猜不到原因。
  static String normalizeUrl(String input) {
    var text = input.trim();
    if (text.length >= 2) {
      final first = text.substring(0, 1);
      final last = text.substring(text.length - 1);
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        text = text.substring(1, text.length - 1).trim();
      }
    }
    if (text.isEmpty) return '';
    final lower = text.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      text = 'https://' + text;
    }
    if (!text.endsWith('/')) text = text + '/';
    return text;
  }

  /// 还是不是"占位模板"（预设里那些 你的域名 / 客户端专用域名）。
  /// 用户没改就点测试连接的话，会得到一句莫名其妙的网络错误；
  /// 所以界面要先拦住，直接说"请把地址换成你自己的"。
  static bool looksLikeTemplate(String input) {
    final text = input.trim();
    if (text.isEmpty) return true;
    return text.contains('你的') ||
        text.contains('客户端专用') ||
        text.contains('example.com');
  }

  /// 脱敏显示（界面上只给看一眼确认没填错）
  static String maskPassword(String value) {
    if (value.isEmpty) return '（未填）';
    if (value.length <= 4) return '****';
    return value.substring(0, 2) + '****' + value.substring(value.length - 2);
  }
}
