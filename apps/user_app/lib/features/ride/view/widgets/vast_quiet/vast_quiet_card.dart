import 'package:flutter/material.dart';

import 'vast_quiet_theme.dart';

/// The frame every Vast Quiet card shares: a white [surface] with a 1px
/// hairline border and the system's single 2px radius. No shadow, no gradient.
///
/// [clip] is on when a card's contents run to its edge (a map header, an action
/// bar) so the corners stay crisp; [padding] is null for those so the child
/// owns its own insets.
class VastQuietCard extends StatelessWidget {
  const VastQuietCard({
    super.key,
    required this.child,
    this.padding,
    this.color = VastQuiet.surface,
    this.border,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color color;

  /// Defaults to the standard hairline; the surge card passes an accent side.
  final BoxBorder? border;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: color,
      border: border ?? Border.all(color: VastQuiet.hairline),
      borderRadius: BorderRadius.circular(VastQuiet.radius),
    );
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: decoration,
      child: child,
    );
  }
}

/// A full-bleed 1px hairline divider in the Vast Quiet ink tint.
class VastQuietDivider extends StatelessWidget {
  const VastQuietDivider({super.key, this.color = VastQuiet.hairline});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color);
}
