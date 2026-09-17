import 'package:flutter/services.dart' show rootBundle;

/// ===== 随包内置的校历（用户 2026-09-17 拍板）=====
///
/// ## 为什么要有它
///
/// 校历来自**上游 Celechron 的第三方静态站** `http://calendar.celechron.top/`：
/// 明文 HTTP、8 秒超时、域名和服务器都不在我们手里 —— 用户实测经常连不上，
/// 一失败就落到"本地缓存"，而缓存为空时只能"本地推算"（节假日/调休全空、考试周不准）。
/// 所以干脆**把那份 JSON 直接打进包里**：离线可用、首次安装就有、
/// 也不用每次刷新都去敲那个站。
///
/// ## 更新方式（同一轮拍板）
///
/// **每周**才去试一次远程；连上了就**比对差异、按新的来**
/// （见 `TimeConfigService.getConfig`）。随包版本跟着 App 版本走 ——
/// 发版时把 `assets/calendar/<学年学期>.json` 换成最新下载的那份即可。
///
/// ## 数据是什么
///
/// 只含**公开的校历信息**（开学/结束日期、节次时间表、节假日、调休、考试周），
/// **不含任何用户数据**。格式与远程接口一致（见 `calendar_config_parser.dart`）。
class BundledCalendarConfig {
  BundledCalendarConfig._();

  /// 读过一次就记住（一个学期内校历不会变，没必要反复读盘）
  static final Map<String, String?> _cache = <String, String?>{};

  /// 读取内置校历；**没有内置就返回 null**（更早的学期、或未来学期还没发布 —— 都属正常）。
  static Future<String?> load(String semesterId) async {
    if (_cache.containsKey(semesterId)) return _cache[semesterId];
    String? text;
    try {
      text = await rootBundle.loadString('assets/calendar/$semesterId.json');
    } catch (_) {
      // 没有这个文件不是错误：调用方继续往下一级兜底（推算配置）。
      text = null;
    }
    _cache[semesterId] = text;
    return text;
  }

  /// 当前随包带了哪几个学期 —— 给测试与"资源是否齐全"的自查用。
  ///
  /// ⚠️ 加/删 `assets/calendar/` 里的文件时**这里要一起改**：
  /// `test/calendar_bundled_test.dart` 会逐个真的去加载，对不上就报错。
  static const List<String> bundledSemesters = <String>[
    '2025-2026-1',
    '2025-2026-2',
    '2026-2027-1',
  ];
}
