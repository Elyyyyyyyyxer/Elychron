import 'package:flutter/foundation.dart';

/// Use the app window, rather than the device model, for iPad layouts.
final class AdaptiveWindow {
  static const double wideBreakpoint = 900;

  static bool isWideIos(double width, TargetPlatform platform) =>
      platform == TargetPlatform.iOS && width >= wideBreakpoint;
}
