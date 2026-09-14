import 'package:flutter/widgets.dart';

/// Text that recognizes only Markdown's `**bold**` syntax.
///
/// All other Markdown syntax is rendered literally. Unmatched `**` markers
/// are also kept as plain text.
class BoldMarkdownText extends StatelessWidget {
  const BoldMarkdownText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @visibleForTesting
  static List<TextSpan> parse(String source) {
    final spans = <TextSpan>[];
    var cursor = 0;

    while (cursor < source.length) {
      final opening = source.indexOf('**', cursor);
      if (opening == -1) {
        spans.add(TextSpan(text: source.substring(cursor)));
        break;
      }

      final closing = source.indexOf('**', opening + 2);
      if (closing == -1) {
        spans.add(TextSpan(text: source.substring(cursor)));
        break;
      }

      if (opening > cursor) {
        spans.add(TextSpan(text: source.substring(cursor, opening)));
      }
      spans.add(TextSpan(
        text: source.substring(opening + 2, closing),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
      cursor = closing + 2;
    }

    if (source.isEmpty) spans.add(const TextSpan(text: ''));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: parse(data)),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
