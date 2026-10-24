import 'package:flutter/material.dart';

import 'skyline_tokens.dart';

/// The Skyline list row: an icon in a tinted rounded well, a title, an
/// optional subtitle and trailing widget. Used for search results, recents and
/// row-style actions ("Use my current location").
///
/// [accent] tints the icon well and title in the brand blue, for rows that are
/// actions rather than data. [leading] replaces the icon (e.g. a spinner).
class SkylineRow extends StatelessWidget {
  const SkylineRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.leading,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final subtitle = this.subtitle;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Skyline.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Skyline.s12,
          vertical: Skyline.s12,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent ? t.primarySoft : t.sunken,
                borderRadius: BorderRadius.circular(Skyline.radiusSm),
              ),
              alignment: Alignment.center,
              child:
                  leading ??
                  Icon(
                    icon,
                    size: 20,
                    color: accent ? t.primaryText : t.inkMuted,
                  ),
            ),
            const SizedBox(width: Skyline.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.title(15, color: accent ? t.primaryText : t.ink),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body(size: 13),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Skyline.s8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A white rounded card with Skyline's soft shadow, grouping rows or fields.
class SkylineCard extends StatelessWidget {
  const SkylineCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Skyline.s8),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Skyline.radiusLg),
        boxShadow: t.cardShadow,
      ),
      child: child,
    );
  }
}

/// A titled form section in its own card — "How long?", "When?", "Which car?".
class SkylineSection extends StatelessWidget {
  const SkylineSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final subtitle = this.subtitle;
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: t.title(16)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: t.body(size: 13)),
          ],
          const SizedBox(height: Skyline.s16),
          child,
        ],
      ),
    );
  }
}

/// The place a trip starts from, shown at the top of the details steps.
class SkylinePlaceSummary extends StatelessWidget {
  const SkylinePlaceSummary({
    super.key,
    required this.label,
    required this.address,
    this.icon = Icons.trip_origin_rounded,
  });

  final String label;
  final String address;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Skyline.s12),
      decoration: BoxDecoration(
        color: t.isDark ? t.sunken : t.primarySoft,
        borderRadius: BorderRadius.circular(Skyline.radiusLg),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(Skyline.radiusSm),
            ),
            child: Icon(icon, size: 20, color: t.primaryText),
          ),
          const SizedBox(width: Skyline.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.label(size: 12, color: t.primaryText)),
                const SizedBox(height: 2),
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.title(15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The white, rounded-top bar pinned under a form, holding the fare and the
/// confirm button. Same shape as [Padding] so it drops in for one.
class SkylineActionBar extends StatelessWidget {
  const SkylineActionBar({super.key, required this.padding, this.child});

  final EdgeInsetsGeometry padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Skyline.radiusXl),
        ),
        boxShadow: t.floatShadow,
      ),
      padding: padding,
      child: child,
    );
  }
}
