import 'package:celechron/design/adaptive_window.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// Centers shared sheets within the visible area of a wide iPad window.
class AdaptiveSheetFrame extends StatelessWidget {
  final Widget child;

  const AdaptiveSheetFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    if (!AdaptiveWindow.isWideIos(
        MediaQuery.sizeOf(context).width, defaultTargetPlatform)) {
      if (defaultTargetPlatform == TargetPlatform.iOS && keyboardInset > 0) {
        return Padding(
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: child,
        );
      }
      return child;
    }

    final mediaQuery = MediaQuery.of(context);
    final topInset = mediaQuery.padding.top + 16;
    final bottomInset = keyboardInset + mediaQuery.padding.bottom + 16;
    return LayoutBuilder(builder: (context, constraints) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, topInset, 16, bottomInset),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: (constraints.maxHeight - topInset - bottomInset)
                  .clamp(0, double.infinity),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: child,
            ),
          ),
        ),
      );
    });
  }
}
