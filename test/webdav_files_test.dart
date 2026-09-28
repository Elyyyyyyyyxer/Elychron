import 'package:celechron/mod/webdav_config.dart';
import 'package:celechron/mod/webdav_files.dart';
import 'package:flutter_test/flutter_test.dart';

/// ===== 全平台同步（W4）：附件本体的纯逻辑 =====
///
/// 这里钉的是"两台设备各自算远端文件名，必须算得一模一样"这件事 ——
/// 它一旦不一致，表现是"手机上明明传了，电脑上就是取不到"，
/// 而两边日志都看不出任何错误。
void main() {
  group('远端文件名', () {
    test('同一条路径永远算出同一个名字（两台设备各自算，必须一致）', () {
      const path =
          '/data/user/0/com.elychron/app_flutter/task_attachments/1_简历.pdf';
      expect(WebDavFiles.remoteNameFor(path), WebDavFiles.remoteNameFor(path));
    });

    test('Windows 的反斜杠与安卓的正斜杠指向同一份文件时名字不同', () {
      // 这是**有意的**：两台设备上的绝对路径本来就不同，
      // 名字里带哈希正是为了让"同名不同文件"不会互相覆盖。
      expect(WebDavFiles.remoteNameFor(r'C:\docs\a.pdf'),
          isNot(WebDavFiles.remoteNameFor('/home/a.pdf')));
    });

    test('同名但不同目录的文件必须分开（否则会互相覆盖）', () {
      expect(WebDavFiles.remoteNameFor('/a/IMG_0001.jpg'),
          isNot(WebDavFiles.remoteNameFor('/b/IMG_0001.jpg')));
    });

    test('保留中文文件名（用户看得懂比什么都重要）与扩展名', () {
      final name = WebDavFiles.remoteNameFor('/x/实验报告 v2.pdf');
      expect(name.endsWith('实验报告_v2.pdf'), isTrue, reason: name);
    });

    test('名字里不会出现路径分隔符或冒号（否则 WebDAV 会当成目录）', () {
      final name = WebDavFiles.remoteNameFor(r'C:\a b:c/d*e?.pdf');
      expect(name.contains('/'), isFalse);
      expect(name.contains('\\'), isFalse);
      expect(name.contains(':'), isFalse);
      expect(name.contains('*'), isFalse);
    });

    test('超长文件名会被截断，但扩展名保住', () {
      final long = 'x' * 200 + '.pdf';
      final name = WebDavFiles.remoteNameFor('/y/' + long);
      final base = name.substring(name.indexOf('_') + 1);
      expect(base.length <= 60, isTrue, reason: base.length.toString());
      expect(base.endsWith('.pdf'), isTrue);
    });
  });

  group('要不要传这个文件', () {
    const mb = 1024 * 1024;
    test('传过且大小没变 → 不传', () {
      expect(
        WebDavFiles.shouldUpload(
          uploadedBytes: 1234,
          size: 1234,
          maxFileBytes: 50 * mb,
          usedThisMonth: 0,
          monthlyBudget: 900 * mb,
        ),
        isFalse,
      );
    });

    test('从没传过 / 大小变了 → 传', () {
      expect(
        WebDavFiles.shouldUpload(
          uploadedBytes: null,
          size: 100,
          maxFileBytes: 50 * mb,
          usedThisMonth: 0,
          monthlyBudget: 900 * mb,
        ),
        isTrue,
      );
      expect(
        WebDavFiles.shouldUpload(
          uploadedBytes: 100,
          size: 200,
          maxFileBytes: 50 * mb,
          usedThisMonth: 0,
          monthlyBudget: 900 * mb,
        ),
        isTrue,
      );
    });

    test('单文件超过上限 → 不传（界面上会说明，不默默跳过）', () {
      expect(
        WebDavFiles.shouldUpload(
          uploadedBytes: null,
          size: 51 * mb,
          maxFileBytes: 50 * mb,
          usedThisMonth: 0,
          monthlyBudget: 900 * mb,
        ),
        isFalse,
      );
    });

    test('本月额度不够 → 不传（宁可少传，也不能把配额跑光）', () {
      expect(
        WebDavFiles.shouldUpload(
          uploadedBytes: null,
          size: 20 * mb,
          maxFileBytes: 50 * mb,
          usedThisMonth: 890 * mb,
          monthlyBudget: 900 * mb,
        ),
        isFalse,
      );
      expect(
        WebDavFiles.shouldUpload(
          uploadedBytes: null,
          size: 5 * mb,
          maxFileBytes: 50 * mb,
          usedThisMonth: 890 * mb,
          monthlyBudget: 900 * mb,
        ),
        isTrue,
      );
    });

    test('空文件不传（没有意义，还占一次请求）', () {
      expect(
        WebDavFiles.shouldUpload(
          uploadedBytes: null,
          size: 0,
          maxFileBytes: 50 * mb,
          usedThisMonth: 0,
          monthlyBudget: 900 * mb,
        ),
        isFalse,
      );
    });
  });

  group('索引与流量', () {
    test('索引能存能读（往返一致）', () {
      final raw = WebDavFiles.encodeIndex(<String, int>{
        'abc_照片.jpg': 2048,
        'def_报告.pdf': 999,
      });
      final back = WebDavFiles.decodeIndex(raw);
      expect(back['abc_照片.jpg'], 2048);
      expect(back['def_报告.pdf'], 999);
    });

    test('索引坏了当没有，不能崩（用户数据要紧）', () {
      expect(WebDavFiles.decodeIndex(null).isEmpty, isTrue);
      expect(WebDavFiles.decodeIndex('').isEmpty, isTrue);
      expect(WebDavFiles.decodeIndex('这不是 JSON').isEmpty, isTrue);
      expect(WebDavFiles.decodeIndex('{"a":"b"}').isEmpty, isTrue);
    });

    test('来源映射往返一致（本机路径 → 网盘名字）', () {
      final raw = WebDavFiles.encodeStringMap(<String, String>{
        r'C:\docs\task_attachments\1_a.pdf': 'abcd1234_a.pdf',
        '/data/user/0/x/files/2_b.jpg': 'ffff0000_b.jpg',
      });
      final back = WebDavFiles.decodeMap(raw);
      expect(back.length, 2);
      expect(back[r'C:\docs\task_attachments\1_a.pdf'], 'abcd1234_a.pdf');
      expect(back['/data/user/0/x/files/2_b.jpg'], 'ffff0000_b.jpg');
    });

    test('来源映射坏了也当没有（与索引同一套容错）', () {
      expect(WebDavFiles.decodeMap(null).isEmpty, isTrue);
      expect(WebDavFiles.decodeMap('坏了').isEmpty, isTrue);
      expect(WebDavFiles.decodeMap('{"a":""}').isEmpty, isTrue);
    });

    test('流量显示成人话', () {
      expect(WebDavFiles.formatBytes(0), '0 B');
      expect(WebDavFiles.formatBytes(999), '999 B');
      expect(WebDavFiles.formatBytes(2048), '2.0 KB');
      expect(WebDavFiles.formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(WebDavFiles.formatBytes(2 * 1024 * 1024 * 1024), '2.00 GB');
    });

    test('流量按月份算（跨月归零）', () {
      expect(WebDavConfig.currentMonthKey(DateTime(2026, 9, 28)), '2026-09');
      expect(WebDavConfig.currentMonthKey(DateTime(2026, 12, 1)), '2026-12');
    });
  });
}
