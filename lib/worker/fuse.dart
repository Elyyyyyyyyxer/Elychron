import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';

import 'package:celechron/database/database_helper.dart';

/// 一次更新检查的结论。
class UpdateInfo {
  /// 远端 release 的 tag，例如 `v1.4.0-elychron.1`
  final String tag;

  /// Release 说明的第一行（做摘要）
  final String summary;

  /// 主版本号变化 → **强制更新**：对话框不可忽略，只能去下载或退出应用。
  final bool forced;

  /// 这次是从哪个源查到的（`GitHub` / `Gitee`）。
  ///
  /// **必须记下来**：国内用户多半连不上 GitHub，如果查到更新的是 Gitee，
  /// 「去下载」就该跳 Gitee 的页面 —— 否则用户看到更新却打不开下载页。
  final String sourceName;

  /// 「去下载」要打开的地址（跟着上面那个源走）
  final String downloadUrl;

  const UpdateInfo({
    required this.tag,
    required this.summary,
    required this.forced,
    required this.sourceName,
    required this.downloadUrl,
  });

  String get message =>
      summary.isEmpty ? '有新版本可用：$tag' : '有新版本可用：$tag\n$summary';
}

/// 一个更新检查源。
///
/// GitHub 是源码主仓库；Gitee 是国内可达的镜像（下载与更新检查都靠它兜底）。
class UpdateSource {
  final String name;
  final String apiUrl;
  final String releasePageUrl;

  const UpdateSource({
    required this.name,
    required this.apiUrl,
    required this.releasePageUrl,
  });
}

class Fuse {
  late DateTime lastUpdateTime;

  final bool isBeta = false;

  /// ===== 版本号（⚠️ 改版本时这四处要一起改）=====
  /// - `pubspec.yaml` 的 `version:`（决定 APK 的 versionName / versionCode）
  /// - 这里的 [appVersionName]（关于页显示的就是它）
  /// - [appBuildNumber]（反馈信息里会带上）
  /// - [version]（用来跟远端 tag 比较）
  static const String appVersionName = '1.4.1-elychron.1';

  /// 构建号，与 `pubspec.yaml` 里 `+N` 保持一致。
  ///
  /// 单独放一个**静态常量**是因为「复制反馈信息」要用它，而那个场景不该去
  /// 实例化 [Fuse]（构造函数依赖 GetX 里的数据库）。
  static const int appBuildNumber = 6;

  final version = [1, 4, 1];
  final build = appBuildNumber;

  /// ===== 更新检查：只认我们自己的仓库 =====
  ///
  /// **绝不要指向上游**（原来是 `api.celechron.top`）。理由：
  /// 1. 上游发版后，我们的用户会看到「有新版本」，然后被引到 celechron.top ——
  ///    等于给自己用户做上游导流；
  /// 2. 他们从那下到的是官方包，而两个 App 的包名不同，
  ///    结果是手机上多出**第二个应用**，用户一脸懵；
  /// 3. 频繁请求别人的服务器本身也不合适。
  static const String releaseRepo = 'Elyyyyyyyyxer/Elychron';
  static const String releasePageUrl =
      'https://github.com/$releaseRepo/releases/latest';
  static const String releaseApiUrl =
      'https://api.github.com/repos/$releaseRepo/releases/latest';

  /// Gitee 镜像仓库（`owner/repo`）。
  ///
  /// 用途：国内直连 GitHub 常常不通，而**更新检查与下载都得能用**，
  /// 所以 Gitee 既是分发渠道也是兜底更新源。留空字符串就只查 GitHub。
  ///
  /// ⚠️ 建好 Gitee 仓库后把这里改成实际的 `用户名/仓库名`。
  static const String giteeRepo = 'P3RF3CT/elychron';

  /// 更新检查的源，按顺序尝试（前面失败就试下一个）
  static List<UpdateSource> get updateSources => <UpdateSource>[
        const UpdateSource(
          name: 'GitHub',
          apiUrl: releaseApiUrl,
          releasePageUrl: releasePageUrl,
        ),
        if (giteeRepo.isNotEmpty)
          const UpdateSource(
            name: 'Gitee',
            apiUrl: 'https://gitee.com/api/v5/repos/$giteeRepo/releases/latest',
            releasePageUrl: 'https://gitee.com/$giteeRepo/releases/latest',
          ),
      ];

  List<int>? remoteVersion;
  int? remoteBuild;
  bool hasNewVersion = false;

  /// 上次**已经提醒过**的版本 tag。
  ///
  /// 用途：小版本更新只提醒一次 —— 否则每天检查一次就会天天弹同一个框。
  /// 大版本（强制更新）不看它，每次启动都提醒。
  String? lastPromptedTag;

  /// 远端主版本号比本机高 → 强制更新。
  ///
  /// 判据是用户定的：**小版本不强制，大版本变化强制**。
  /// 例：1.4.0 → 1.5.0 只提醒；1.4.0 → 2.0.0 必须更新后才能用。
  bool get isMajorUpdate {
    final remote = remoteVersion;
    if (remote == null) return false;
    return isMajorBump(remote, version);
  }

  /// 远端比本机新（纯函数，便于单测）
  static bool isNewer(
    List<int> remote,
    List<int> local, {
    int? remoteBuild,
    int? localBuild,
  }) {
    for (var i = 0; i < 3; i++) {
      final r = i < remote.length ? remote[i] : 0;
      final l = i < local.length ? local[i] : 0;
      if (r != l) return r > l;
    }
    if (remoteBuild != null && localBuild != null && remoteBuild != localBuild) {
      return remoteBuild > localBuild;
    }
    return false;
  }

  /// 主版本号（第一段）是否变大
  static bool isMajorBump(List<int> remote, List<int> local) {
    if (remote.isEmpty || local.isEmpty) return false;
    return remote[0] > local[0];
  }

  /// 这次要不要打扰用户（纯函数，便于单测）
  ///
  /// - 没更新 → 不打扰
  /// - 强制更新 → 每次都提醒
  /// - 小版本 → 同一个 tag 只提醒一次
  static bool shouldPrompt({
    required bool hasNew,
    required bool forced,
    required String tag,
    required String? lastPromptedTag,
  }) {
    if (!hasNew) return false;
    if (forced) return true;
    return lastPromptedTag != tag;
  }

  final HttpClient _httpClient = HttpClient();
  final DatabaseHelper _db = Get.find<DatabaseHelper>(tag: 'db');

  String get displayVersion => appVersionName + (isBeta ? ' beta' : '');

  Fuse() {
    lastUpdateTime = DateTime(2001, 1, 1);
  }

  /// 从 tag 里取出 `1.4.0` 这样的版本号：`v1.4.0-elychron.1` → `[1, 4, 0]`。
  static List<int>? parseTagVersion(String tag) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(tag);
    if (match == null) return null;
    return [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }

  /// 取 Release 说明的第一行有意义的内容，塞进弹窗里当一句话摘要。
  static String _firstLineOf(Object? body) {
    if (body is! String) return '';
    for (final line in body.split('\n')) {
      final text = line.replaceAll(RegExp(r'^[#\-\*\s]+'), '').trim();
      if (text.isEmpty) continue;
      return text.length > 60 ? '${text.substring(0, 60)}…' : text;
    }
    return '';
  }

  /// 查一个源，拿到它的 release JSON。失败（网络不通/非 200/结构不对）返回 null。
  Future<Map<String, dynamic>?> _fetchRelease(UpdateSource source) async {
    try {
      final request = await _httpClient
          .getUrl(Uri.parse(source.apiUrl))
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 8));
      // 还没发过 Release 时通常给 404：当作「这个源没东西」，安静换下一个
      if (response.statusCode != 200) return null;
      final raw = await response.transform(utf8.decoder).join();
      final json = jsonDecode(raw);
      return json is Map ? Map<String, dynamic>.from(json) : null;
    } catch (e) {
      return null;
    }
  }

  Future<UpdateInfo?> checkUpdate() async {
    try {
      if (lastUpdateTime
          .isAfter(DateTime.now().subtract(const Duration(days: 1)))) {
        return null;
      }

      // 依次尝试各个源：GitHub 在国内常常连不上，Gitee 是兜底。
      // 只要有一个源给了合法结果就用它，并记住是哪个源 —— 「去下载」要跳对地方。
      UpdateSource? answered;
      Map<String, dynamic>? json;
      String tag = '';
      List<int>? parsed;
      for (final source in updateSources) {
        final data = await _fetchRelease(source);
        if (data == null) continue;
        final candidateTag = '${data['tag_name'] ?? ''}';
        final candidateVersion = parseTagVersion(candidateTag);
        if (candidateVersion == null) continue;
        answered = source;
        json = data;
        tag = candidateTag;
        parsed = candidateVersion;
        break;
      }

      // 所有源都没结果：安静跳过（不写 lastUpdateTime，下次启动还会再试）
      if (answered == null || json == null || parsed == null) return null;

      remoteVersion = parsed;
      // 我们自己的 tag 不带 versionCode，只比版本号本身
      remoteBuild = build;
      hasNewVersion = _compareVersion(false);
      lastUpdateTime = DateTime.now();

      if (!hasNewVersion) {
        await _db.setFuse(this);
        return null;
      }

      final forced = isMajorUpdate;
      // 小版本只提醒一次：同一个 tag 已经提醒过就不再弹，否则每天都会烦一次
      if (!shouldPrompt(
        hasNew: true,
        forced: forced,
        tag: tag,
        lastPromptedTag: lastPromptedTag,
      )) {
        await _db.setFuse(this);
        return null;
      }
      if (!forced) lastPromptedTag = tag;
      await _db.setFuse(this);

      return UpdateInfo(
        tag: tag,
        summary: _firstLineOf(json['body']),
        forced: forced,
        sourceName: answered.name,
        downloadUrl: answered.releasePageUrl,
      );
    } catch (e) {
      // 网络不通、JSON 结构变了、被限流……一律安静跳过，不影响任何本地功能
      return null;
    }
  }

  bool _compareVersion(bool remoteIsBeta) {
    if (remoteVersion == null || remoteBuild == null) {
      return false;
    }
    if (remoteVersion![0] > version[0]) {
      return true;
    } else if (remoteVersion![0] == version[0]) {
      if (remoteVersion![1] > version[1]) {
        return true;
      } else if (remoteVersion![1] == version[1]) {
        if (remoteVersion![2] > version[2]) {
          return true;
        } else if (remoteVersion![2] == version[2]) {
          if (remoteBuild! > build) {
            return true;
          } else if (remoteBuild == build) {
            if (isBeta && !remoteIsBeta) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'lastUpdateTime': lastUpdateTime.toIso8601String(),
        // 小版本「只提醒一次」要跨启动保持，所以得存下来
        'lastPromptedTag': lastPromptedTag,
      };

  Fuse.fromJson(Map<String, dynamic> json) {
    lastUpdateTime = DateTime.parse(json['lastUpdateTime']);
    lastPromptedTag = json['lastPromptedTag'] as String?;
  }
}
