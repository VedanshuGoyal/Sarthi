import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../core/theme/deep_signal/deep_signal_theme.dart';
import 'view/splash_screen.dart';

/// Registers both Deep Signal modes so the splash renders either.
PreviewThemeData splashPreviewTheme() => PreviewThemeData(
  materialLight: DeepSignalTheme.light(),
  materialDark: DeepSignalTheme.dark(),
);

@Preview(name: 'Splash', group: 'Splash', theme: splashPreviewTheme)
Widget splashPreview() => const SplashScreen();

/// A phone-sized frame, to check the lockup and the signal bar at the size
/// they actually ship at rather than at the preview pane's dimensions.
@Preview(
  name: 'Splash — phone',
  group: 'Splash',
  size: Size(390, 844),
  theme: splashPreviewTheme,
)
Widget splashPhonePreview() => const SplashScreen();

/// The tablet case, where `SplashScreen` clamps the mark rather than letting it
/// scale with the (much larger) shortest edge.
@Preview(
  name: 'Splash — tablet',
  group: 'Splash',
  size: Size(834, 1112),
  theme: splashPreviewTheme,
)
Widget splashTabletPreview() => const SplashScreen();
