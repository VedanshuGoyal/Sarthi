import 'package:flutter/material.dart';

import '../deep_signal_tokens.dart';

/// The frame every Deep Signal card shares: a [surface] fill with a 1px hairline
/// border and the system's single 2px radius. No shadow, no gradient — surfaces
/// separate by value alone, so this reads correctly in both modes.
///
/// [clip] is on when a card's contents run to its edge (a map header, an action
/// bar) so the corners stay crisp; [padding] is null for those so the child owns
/// its own insets.
class DeepSignalCard extends StatelessWidget {
  const DeepSignalCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.border,
    this.clip = false,
    this.width,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Defaults to the mode's [DeepSignalTokens.surface].
  final Color? color;

  /// Defaults to the standard hairline; the surge card passes an accent side.
  final BoxBorder? border;
  final bool clip;

  /// An optional fixed width — cards in the set are drawn at 390.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    final card = Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color ?? t.surface,
        border: border ?? Border.all(color: t.hairline),
        borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
      ),
      child: child,
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// A full-bleed 1px hairline divider in the mode's hairline tint.
class DeepSignalDivider extends StatelessWidget {
  const DeepSignalDivider({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: color ?? DeepSignalTokens.of(context).hairline);
}
