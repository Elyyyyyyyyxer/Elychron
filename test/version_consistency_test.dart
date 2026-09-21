import 'dart:io';

import 'package:celechron/worker/fuse.dart';
import 'package:flutter_test/flutter_test.dart';

/// 版本号**不能再漂移**（2026-09-21 踩过）。
///
/// 起因：用户在手机上导出的反馈信息里写着「版本：1.4.1-elychron.1 (build 9)」，
/// 而手机上实际装的已经是 1.4.2 (build 10)（dumpsys 核对过）。
/// 因为反馈信息里的版本读的是 fuse.dart 里**手写死的常量**，
/// 改 pubspec 时忘了同步它 —— 于是排查时被自己的版本号误导了半天。
///
/// 这条测试把常量与 pubspec.yaml 钉在一起：以后改版本忘了同步，测试直接红。
void main() {
  test('fuse.dart 里的版本常量与 pubspec.yaml 一致', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere(
      (String item) => item.startsWith('version:'),
      orElse: () => '',
    );
    expect(line, isNotEmpty, reason: 'pubspec.yaml 里应该有 version:');

    // 形如 version: 1.4.2-elychron.1+10
    final raw = line.split(':').last.trim();
    final plus = raw.lastIndexOf('+');
    final name = plus > 0 ? raw.substring(0, plus) : raw;
    final build = plus > 0 ? raw.substring(plus + 1) : '';

    expect(Fuse.appVersionName, name,
        reason: 'fuse.dart 的 appVersionName 与 pubspec 不一致（改版本时两处都要改）');
    if (build.isNotEmpty) {
      expect(Fuse.appBuildNumber.toString(), build,
          reason: 'fuse.dart 的 appBuildNumber 与 pubspec 的 +N 不一致');
    }
  });
}
