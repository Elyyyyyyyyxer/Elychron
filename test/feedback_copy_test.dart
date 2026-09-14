import 'package:celechron/mod/feedback_copy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「复制反馈信息」的文本裁剪规则。
///
/// 反馈会发生在 QQ 群、论坛帖这类地方 —— 粘太长没人看，粘太短又定位不了问题，
/// 所以日志取**尾部**固定行数，且要剔掉空行。
void main() {
  test('日志行数不够时原样返回（剔除空行）', () {
    const text = '第一行\n\n第二行\n   \n第三行';
    expect(FeedbackCopy.tailLines(text, 10), '第一行\n第二行\n第三行');
  });

  test('超长时取尾部 —— 现场在最后，所以要截尾不是截头', () {
    final lines = List.generate(10, (i) => 'line$i');
    final result = FeedbackCopy.tailLines(lines.join('\n'), 3);
    expect(result, 'line7\nline8\nline9');
  });

  test('正好等于上限时不裁剪', () {
    final lines = List.generate(5, (i) => 'l$i');
    expect(FeedbackCopy.tailLines(lines.join('\n'), 5), lines.join('\n'));
  });

  test('上限为 0 或负数时返回空串（不抛异常）', () {
    expect(FeedbackCopy.tailLines('a\nb', 0), '');
    expect(FeedbackCopy.tailLines('a\nb', -1), '');
  });

  test('空日志不炸', () {
    expect(FeedbackCopy.tailLines('', 10), '');
    expect(FeedbackCopy.tailLines('\n\n\n', 10), '');
  });

  test('行尾空白会被清掉（免得复制出一堆空格）', () {
    expect(FeedbackCopy.tailLines('abc   \ndef\t\n', 10), 'abc\ndef');
  });

  test('默认带 120 行日志（够定位，又不至于没法粘贴）', () {
    expect(FeedbackCopy.logTailLines, 120);
  });
}
