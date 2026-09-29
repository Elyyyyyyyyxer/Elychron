import 'package:celechron/design/adaptive_window.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// Bounds task form width while keeping its scroll view at full page height.
class AdaptiveFormBody extends StatelessWidget {
  final Widget child;

  const AdaptiveFormBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide =
          AdaptiveWindow.isWideIos(constraints.maxWidth, defaultTargetPlatform);
      final width =
          isWide && constraints.maxWidth > 720 ? 720.0 : constraints.maxWidth;
      return Center(
        child: SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: child,
        ),
      );
    });
  }
}

extension AdaptiveFormBodyExtension on Widget {
  Widget asAdaptiveFormBody() => AdaptiveFormBody(child: this);
}
