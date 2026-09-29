import 'dart:math' as math;

import 'package:celechron/design/adaptive_window.dart';
import 'package:celechron/page/desktop/desktop_nav_rail.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// Swaps the main navigation chrome without replacing the current page.
class AdaptiveHomeBody extends StatelessWidget {
  const AdaptiveHomeBody({
    super.key,
    required this.content,
    required this.bottomBar,
    required this.selectedIndex,
    required this.onSelect,
  });

  static const double wideBreakpoint = AdaptiveWindow.wideBreakpoint;
  static const double maxContentWidth = 920;
  static const double railWidth = 208;

  final Widget content;
  final CupertinoTabBar bottomBar;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide =
          AdaptiveWindow.isWideIos(constraints.maxWidth, defaultTargetPlatform);
      final media = MediaQuery.of(context);
      var contentMedia = media.removeViewInsets(removeBottom: true);
      if (!wide && bottomBar.preferredSize.height > media.viewInsets.bottom) {
        contentMedia = contentMedia.copyWith(
          padding: contentMedia.padding.copyWith(
            bottom: bottomBar.preferredSize.height + media.padding.bottom,
          ),
        );
      }

      return DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoTheme.of(context).scaffoldBackgroundColor,
        ),
        child: Stack(
          children: [
            // Keep the PageView at the same element position while resizing.
            Positioned.fill(
              left: wide ? railWidth : 0,
              child: MediaQuery(
                data: contentMedia,
                child: Padding(
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  child: LayoutBuilder(builder: (context, contentConstraints) {
                    final width = wide
                        ? math.min(maxContentWidth, contentConstraints.maxWidth)
                        : contentConstraints.maxWidth;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: width,
                        height: contentConstraints.maxHeight,
                        child: content,
                      ),
                    );
                  }),
                ),
              ),
            ),
            if (wide)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: DesktopNavRail(
                  index: selectedIndex,
                  onSelect: onSelect,
                  width: railWidth,
                  showDropHint: false,
                ),
              ),
            if (!wide)
              MediaQuery.withNoTextScaling(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: bottomBar,
                ),
              ),
          ],
        ),
      );
    });
  }
}
