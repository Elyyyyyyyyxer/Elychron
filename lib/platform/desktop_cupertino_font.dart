import 'dart:io';
import 'dart:typed_data';

import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/services.dart';

/// ===== 桌面端：把系统字体注册成 Cupertino 组件用的族名（v1.5.0）=====
///
/// 要解决的问题（用户 2026-09-19 反馈"很多弹窗的字体没改"）：
///
/// Flutter 的 Cupertino 组件（弹窗、上下文菜单、菜单锚点……）在源码里把字体
/// 写死成 «fontFamily: 'CupertinoSystemText'»，而且 «inherit: false» ——
/// 这两个一起意味着：**主题、DefaultTextStyle.merge、copyWith 全都管不到它**。
/// 全项目有 50 处 CupertinoAlertDialog，逐个加样式不现实，也不该那么写。
///
/// 但 Flutter 允许运行期用 [FontLoader] 往任意族名里塞字体 ——
/// 于是这里把 Windows 自带的微软雅黑按 «CupertinoSystemText» 这个族名注册进去：
/// - 只对桌面端生效（手机端不注册，保持系统原生字体）；
/// - 不往包里塞字体文件（直接读系统字体，包体不变）；
/// - 之前设的主题字体仍然管普通文本，这里补上的是"写死族名"的那一批。
///
/// 读不到系统字体时安静放弃（退回平台默认回退字体，功能不受影响）。
void _log(String message) {
  try {
    DiagnosticLogService.instance
        .record(module: '桌面字体', operation: 'register', message: message);
  } catch (_) {}
}

Future<void> registerDesktopCupertinoFont() async {
  if (!PlatformFeatures.isDesktop) return;
  // 微软雅黑优先；它是 .ttc（字体集合），万一引擎不认就退到两个 .ttf
  const candidates = <String>[
    'C:\\Windows\\Fonts\\msyh.ttc', // 微软雅黑（Win10/11 的正式名字）
    'C:\\Windows\\Fonts\\msyh.ttf',
    'C:\\Windows\\Fonts\\Deng.ttf', // 等线
    'C:\\Windows\\Fonts\\simhei.ttf', // 黑体
  ];
  for (final path in candidates) {
    try {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = await file.readAsBytes();
      final loader = FontLoader('CupertinoSystemText')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      _log('已把 ' + path + ' 注册为 CupertinoSystemText');
      // 同时打到标准输出：桌面端调试时用重定向就能看到（诊断日志是攒着落盘的）
      // ignore: avoid_print
      print('[font] CupertinoSystemText <- ' + path);
      return;
    } catch (error) {
      _log('注册失败(' + path + ')：' + error.toString());
      // 这个候选不行就试下一个；都不行就安静退回
    }
  }
  _log('没找到可用的系统字体，弹窗字体退回平台默认');
}
