import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// ===== WebDAV 客户端（全平台同步 W1）=====
///
/// 目标：把已经做好的同步引擎（DataBundle + DataMerge + 墓碑 + 冲突选择）
/// 从"局域网直连"搬到"网盘"，让两台设备隔着互联网也能同步。
///
/// 为什么自己写而不是引第三方包：
/// · 我们只用四个动作（PROPFIND / MKCOL / PUT / GET），一个文件就够；
/// · 少一个依赖就少一处平台适配（桌面 + 安卓两端都要能用）；
/// · 关键是**省流量那条**（先问元数据、再决定要不要下载）需要自己掌控请求细节。
///
/// 认证用最通用的 **Basic**（用户名 + 应用密码）——
/// 坚果云/Koofr/Nextcloud/NAS 全都支持这一套。
class WebDavClient {
  WebDavClient({
    required String baseUrl,
    required String username,
    required this.password,
    Duration? timeout,
  })  : baseUrl = _normalizeBase(baseUrl),
        username = username.trim(),
        timeout = timeout ?? const Duration(seconds: 20);

  /// 形如 https://dav.jianguoyun.com/dav/（末尾一定有斜杠）
  final String baseUrl;

  /// 用户名。
  ///
  /// **不是 final**：坚果云要求用户名全小写（实测 2026-09-28：
  /// TixerOfficial@… → 401、tixerofficial@… → 207），
  /// 而 Nextcloud 那类自建服务的用户名大小写敏感，不能无条件小写。
  /// 所以由 selfCheck 先按原样试、401 再换成小写重试一次（见 mod/webdav_sync.dart）。
  String username;
  final String password;
  final Duration timeout;

  static String _normalizeBase(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'https://' + text;
    }
    if (!text.endsWith('/')) text += '/';
    return text;
  }

  String get _authHeader =>
      'Basic ' + base64Encode(utf8.encode(username + ':' + password));

  /// 把相对路径拼到 base 上（逐段编码，中文目录名也能用）
  Uri uriOf(String path) {
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    final encoded = clean
        .split('/')
        .where((String segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return Uri.parse(baseUrl + encoded);
  }

  HttpClient _http() => HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = 'Elychron-WebDAV';

  // ------------------------------------------------------------ 基础动作

  /// PROPFIND：只拿元数据（**不下载内容**）
  ///
  /// [depth] 0 = 只问这个文件/目录自己；1 = 连它下面的直接子项一起问。
  /// 这就是"省流量"的第一层：一个请求就知道远端改没改。
  Future<List<WebDavEntry>> propfind(String path, {int depth = 0}) async {
    final client = _http();
    try {
      final request = await client.openUrl('PROPFIND', uriOf(path));
      request.headers.set(HttpHeaders.authorizationHeader, _authHeader);
      request.headers.set('Depth', depth.toString());
      request.headers.contentType =
          ContentType('application', 'xml', charset: 'utf-8');
      request.write(_propfindBody);
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != 207 && response.statusCode != 200) {
        throw WebDavException(
            response.statusCode, _explain(response.statusCode));
      }
      return parseMultiStatus(text, baseUrl);
    } on SocketException catch (error) {
      throw WebDavException(0, '连不上：' + error.message);
    } finally {
      client.close(force: true);
    }
  }

  /// 只看一个路径的元数据（不存在返回 null）
  Future<WebDavEntry?> stat(String path) async {
    try {
      final entries = await propfind(path, depth: 0);
      for (final entry in entries) {
        if (_samePath(entry.path, path)) return entry;
      }
      return entries.isEmpty ? null : entries.first;
    } on WebDavException catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }

  /// 建目录（已存在不算错 —— WebDAV 里 MKCOL 撞已有目录会回 405）
  ///
  /// 支持多级：a/b/c 会把 a、a/b 一并建好（父目录不存在时 MKCOL 会失败）
  Future<void> ensureDirectory(String path) async {
    final clean = path.replaceAll(RegExp(r'^/+|/+$'), '');
    if (clean.isEmpty) return;
    final segments = clean.split('/');
    var current = '';
    for (final segment in segments) {
      current = current.isEmpty ? segment : current + '/' + segment;
      final client = _http();
      try {
        final request = await client.openUrl('MKCOL', uriOf(current));
        request.headers.set(HttpHeaders.authorizationHeader, _authHeader);
        final response = await request.close().timeout(timeout);
        await response.drain<void>();
        // 201 建好了 / 405 已经有了 / 301、302 有些服务会重定向一次
        if (response.statusCode == 201 ||
            response.statusCode == 204 ||
            response.statusCode == 405 ||
            response.statusCode == 301 ||
            response.statusCode == 302) {
          continue;
        }
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw WebDavException(response.statusCode, '账号或应用密码不对，或者没有写权限');
        }
        throw WebDavException(
            response.statusCode, _explain(response.statusCode));
      } finally {
        client.close(force: true);
      }
    }
  }

  /// 上传（父目录要先 ensureDirectory）
  Future<void> put(String path, List<int> bytes) async {
    final client = _http();
    try {
      final request = await client.putUrl(uriOf(path));
      request.headers.set(HttpHeaders.authorizationHeader, _authHeader);
      request.headers.contentType = ContentType.binary;
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 201 &&
          response.statusCode != 204 &&
          response.statusCode != 200) {
        throw WebDavException(
            response.statusCode, _explain(response.statusCode) + ' ' + body);
      }
    } on SocketException catch (error) {
      throw WebDavException(0, '连不上：' + error.message);
    } finally {
      client.close(force: true);
    }
  }

  /// 下载（不存在返回 null）
  Future<Uint8List?> get(String path) async {
    final client = _http();
    try {
      final request = await client.getUrl(uriOf(path));
      request.headers.set(HttpHeaders.authorizationHeader, _authHeader);
      final response = await request.close().timeout(timeout);
      if (response.statusCode == 404) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw WebDavException(
            response.statusCode, _explain(response.statusCode));
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on SocketException catch (error) {
      throw WebDavException(0, '连不上：' + error.message);
    } finally {
      client.close(force: true);
    }
  }

  /// 删掉一个文件（不存在也算成功）
  Future<void> delete(String path) async {
    final client = _http();
    try {
      final request = await client.deleteUrl(uriOf(path));
      request.headers.set(HttpHeaders.authorizationHeader, _authHeader);
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      if (response.statusCode == 404 ||
          response.statusCode == 204 ||
          response.statusCode == 200) {
        return;
      }
      throw WebDavException(response.statusCode, _explain(response.statusCode));
    } finally {
      client.close(force: true);
    }
  }

  static const String _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:getetag/><d:getlastmodified/><d:getcontentlength/><d:resourcetype/>'
      '</d:prop></d:propfind>';

  /// 把状态码翻成人话（用户看到的提示要能指导下一步动作）
  String _explain(int status) {
    if (status == 401) return '账号或应用密码不对（注意：多数网盘要用**应用密码**，不是登录密码）';
    if (status == 403) return '这个账号没有权限访问该目录';
    if (status == 404) return '远端没有这个路径';
    if (status == 405) return '该服务不支持这个操作';
    if (status == 507) return '网盘空间不够了';
    if (status == 0) return '网络不通';
    // 坚果云那类网盘在"短时间内请求太多"时用 503 限流（不是真宕机；
    // 社区里 remotely-save 那些插件踩的都是这个坑）。说清是限流，
    // 用户才知道该"等一会儿再试"，而不是跑去改账号密码。
    if (status == 503) return '网盘暂时拒绝了这次请求（多半是限流：短时间内请求太多），过几分钟再试就好';
    return 'WebDAV 返回 HTTP ' + status.toString();
  }

  bool _samePath(String a, String b) {
    String norm(String value) =>
        Uri.decodeComponent(value).replaceAll(RegExp(r'^/+|/+$'), '');
    return norm(a) == norm(b);
  }

  // ------------------------------------------------- 解析（纯函数，可单测）

  /// 解析 207 Multi-Status（**纯函数**，方便单测钉住各家网盘的差异）
  ///
  /// 各家的 XML 前缀五花八门（d: / D: / lp1: / 无前缀），
  /// 所以这里全部用**正则**取值，不做严格的 XML 解析 —— 稳、且没有额外依赖。
  static List<WebDavEntry> parseMultiStatus(String xml, String baseUrl) {
    final entries = <WebDavEntry>[];
    final responseBlocks = RegExp(
            r'<(?:[A-Za-z0-9]+:)?response[\s>][\s\S]*?</(?:[A-Za-z0-9]+:)?response>')
        .allMatches(xml);
    for (final block in responseBlocks) {
      final text = block.group(0) ?? '';
      if (text.isEmpty) continue;
      final href = _tag(text, 'href');
      final etag = _tag(text, 'getetag');
      final modified = _tag(text, 'getlastmodified');
      final length = _tag(text, 'getcontentlength');
      final isCollection =
          RegExp(r'<(?:[A-Za-z0-9]+:)?collection\s*/?>').hasMatch(text);
      if (href == null) continue;
      entries.add(WebDavEntry(
        path: _pathFromHref(href, baseUrl),
        etag: etag?.replaceAll('"', ''),
        modifiedAt: modified == null ? null : _parseHttpDate(modified),
        size: length == null ? null : int.tryParse(length),
        isDirectory: isCollection,
      ));
    }
    return entries;
  }

  static String? _tag(String xml, String name) {
    final match = RegExp('<(?:[A-Za-z0-9]+:)?' +
            name +
            r'[^>]*>([\s\S]*?)</(?:[A-Za-z0-9]+:)?' +
            name +
            '>')
        .firstMatch(xml);
    return match?.group(1)?.trim();
  }

  static String _pathFromHref(String href, String baseUrl) {
    var text = Uri.decodeComponent(href.trim());
    try {
      final base = Uri.parse(baseUrl);
      // href 里通常已经带了 base 的路径（base=.../dav/、href=/dav/Elychron/...），
      // 直接拼 baseUrl + href 会多出一段 —— 单测抓到过。
      final Uri target;
      if (text.startsWith('http://') || text.startsWith('https://')) {
        target = Uri.parse(text);
      } else if (text.startsWith('/')) {
        target = base.replace(path: text);
      } else {
        target = base.resolve(text);
      }
      // 只留相对 base 的那一段
      if (target.path.startsWith(base.path)) {
        return target.path.substring(base.path.length);
      }
      return target.path.replaceAll(RegExp(r'^/+'), '');
    } catch (_) {
      return text.replaceAll(RegExp(r'^/+'), '');
    }
  }

  /// HTTP 日期（RFC 1123）：Wed, 21 Oct 2015 07:28:00 GMT
  static DateTime? _parseHttpDate(String raw) {
    try {
      return HttpDate.parse(raw);
    } catch (_) {
      return DateTime.tryParse(raw);
    }
  }
}

/// 远端一个条目（文件或目录）的元数据
class WebDavEntry {
  final String path;
  final String? etag;
  final DateTime? modifiedAt;
  final int? size;
  final bool isDirectory;

  const WebDavEntry({
    required this.path,
    this.etag,
    this.modifiedAt,
    this.size,
    this.isDirectory = false,
  });

  /// ETag 优先（最准），没有就退回"最后修改时间 + 大小"
  String get fingerprint {
    if (etag != null && etag!.isNotEmpty) return etag!;
    final at = modifiedAt?.toIso8601String() ?? '-';
    return at + ':' + (size?.toString() ?? '-');
  }

  @override
  String toString() => 'WebDavEntry($path, $fingerprint, dir=$isDirectory)';
}

class WebDavException implements Exception {
  final int status;
  final String message;
  WebDavException(this.status, this.message);
  @override
  String toString() => message;
}

/// 给测试用的转发（解析逻辑是纯函数，单独测最省事）
List<WebDavEntry> parseMultiStatusForTest(String xml, String baseUrl) =>
    WebDavClient.parseMultiStatus(xml, baseUrl);
