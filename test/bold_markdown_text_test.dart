import 'package:celechron/design/bold_markdown_text.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renders paired double asterisks as bold', () {
    final spans = BoldMarkdownText.parse('before **bold** after');

    expect(spans.map((span) => span.text), ['before ', 'bold', ' after']);
    expect(spans[0].style, isNull);
    expect(spans[1].style?.fontWeight, FontWeight.bold);
    expect(spans[2].style, isNull);
  });

  test('supports multiple bold ranges', () {
    final spans = BoldMarkdownText.parse('**one** and **two**');

    expect(spans.map((span) => span.text), ['one', ' and ', 'two']);
    expect(spans[0].style?.fontWeight, FontWeight.bold);
    expect(spans[2].style?.fontWeight, FontWeight.bold);
  });

  test('leaves other Markdown syntax unchanged', () {
    final spans = BoldMarkdownText.parse('# title _italic_ [link](url) `code`');

    expect(spans.single.text, '# title _italic_ [link](url) `code`');
    expect(spans.single.style, isNull);
  });

  test('leaves unmatched markers unchanged', () {
    final spans = BoldMarkdownText.parse('before **unfinished');

    expect(spans.single.text, 'before **unfinished');
    expect(spans.single.style, isNull);
  });
}
