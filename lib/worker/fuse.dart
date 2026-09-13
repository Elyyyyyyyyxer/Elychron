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

  const UpdateInfo({
    required this.tag,
    required this.summary,
    required this.forced,
  });

  String get message =>
      summary.isEmpty ? '有新版本可用：$tag' : '有新版本可用：$tag\n$summary';
}

class Fuse {
  late DateTime lastUpdateTime;

  final bool isBeta = false;

  /// ===== 版本号（⚠️ 改版本时这三处要一起改）=====
  /// - `pubspec.yaml` 的 `version:`（决定 APK 的 versionName / versionCode）
  /// - 这里的 [appVersionName]（关于页显示的就是它）
  /// - [version]（用来跟远端 tag 比较）
  static const String appVersionName = '1.4.0-elychron.1';
  final version = [1, 4, 0];
  final build = 5;

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

  Future<UpdateInfo?> checkUpdate() async {
    try {
      if (lastUpdateTime
          .isAfter(DateTime.now().subtract(const Duration(days: 1)))) {
        return null;
      }

      final request = await _httpClient
          .getUrl(Uri.parse(releaseApiUrl))
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 8));
      // 还没发过 Release 时 GitHub 会给 404：当作「没有更新」，不打扰用户
      if (response.statusCode != 200) return null;
      final raw = await response.transform(utf8.decoder).join();

      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final tag = '${json['tag_name'] ?? ''}';
      final parsed = parseTagVersion(tag);
      if (parsed == null) return null;

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
