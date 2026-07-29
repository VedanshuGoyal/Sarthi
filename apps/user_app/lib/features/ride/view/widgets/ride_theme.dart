import 'package:flutter/material.dart';

import '../../../../core/theme/deep_signal/deep_signal.dart';
import 'vast_quiet/vast_quiet_theme.dart';

/// The theme the ride screens wrap themselves in.
///
/// It is the app-wide [DeepSignalTheme] (so ride screens follow the OS setting
/// and the in-app toggle like the rest of the app) plus a mode-appropriate
/// [RideSurfaces] wash. Read-only info panels tint themselves via
/// [RideSurfaces.washOf]; supplying the wash here keeps that fill legible in
/// both light and dark instead of falling back to the ultramarine wash.
ThemeData rideSurfaceTheme(BuildContext context) {
  final base = Theme.of(context);
  final tokens = DeepSignalTokens.of(context);
  final wash = tokens.isDark ? tokens.raised : const Color(0xFFEAF1F8);
  return base.copyWith(
    extensions: [...base.extensions.values, RideSurfaces(wash: wash)],
  );
}
