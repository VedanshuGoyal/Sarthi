import 'package:flutter/material.dart';

// ignore: unused_import
import 'vast_quiet/vast_quiet_theme.dart' show RideSurfaces;

/// The theme the ride screens wrap themselves in.
///
/// The app-wide Skyline theme already installs the mode-appropriate
/// [RideSurfaces] wash that read-only info panels tint themselves with, so the
/// ride screens simply use it; kept as a seam for ride-specific overrides.
ThemeData rideSurfaceTheme(BuildContext context) => Theme.of(context);
