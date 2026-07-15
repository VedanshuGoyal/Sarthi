import 'package:flutter/material.dart';

/// The Sarthi brand palette.
///
/// [ultramarine] (`#120A8F`) is the single brand colour both apps build on; it
/// is the seed for [SarthiTheme] and the default for primary actions. The other
/// entries are convenience tones derived from it for surfaces and dividers.
abstract final class SarthiColors {
  /// Sarthi ultramarine blue — the primary brand colour.
  static const Color ultramarine = Color(0xFF120A8F);

  /// A lighter ultramarine tint, useful for hovered/pressed surfaces.
  static const Color ultramarineLight = Color(0xFF3A2FB8);

  /// A very light wash of ultramarine for selected backgrounds and chips.
  static const Color ultramarineWash = Color(0xFFEAE8F7);

  /// Neutral page background behind cards and forms.
  static const Color surface = Color(0xFFF7F8FB);

  /// Muted text / hint colour that still passes contrast on [surface].
  static const Color muted = Color(0xFF6B6F80);
}
