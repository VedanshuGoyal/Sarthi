import 'package:flutter/material.dart';

import 'package:sarthi_shared/sarthi_shared.dart';

/// One choice in the trip chooser.
///
/// Two shapes: [featured] is the wide hero card (deep navy fill, white type,
/// icon on the right) used for the most-booked trip; the regular card is a
/// white tile with a signal-blue icon well. A selected regular card gains a
/// signal-blue ring and check. Renders data and emits [onTap] only.
class TripOptionCard extends StatelessWidget {
  const TripOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.featured = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Draw as the wide, filled hero card.
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final radius = BorderRadius.circular(Skyline.radiusLg);

    final Widget content = featured
        ? Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.title(19, color: t.onPrimary)),
                    const SizedBox(height: Skyline.s4),
                    Text(
                      subtitle,
                      style: t.body(
                        size: 13,
                        color: t.onPrimary.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Skyline.s16),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: t.signal.withValues(alpha: t.isDark ? 0.0 : 1.0),
                  borderRadius: BorderRadius.circular(Skyline.radius),
                  border: t.isDark
                      ? Border.all(color: t.onPrimary.withValues(alpha: 0.3))
                      : null,
                ),
                child: Icon(icon, color: t.onPrimary, size: 28),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: t.primarySoft,
                      borderRadius: BorderRadius.circular(Skyline.radiusSm),
                    ),
                    child: Icon(icon, color: t.primaryText, size: 22),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: Skyline.motion,
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: t.signal,
                      size: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Skyline.s12),
              Text(title, style: t.title(15)),
              const SizedBox(height: Skyline.s4),
              Text(subtitle, style: t.body(size: 12.5)),
            ],
          );

    return AnimatedContainer(
      duration: Skyline.motion,
      curve: Skyline.easing,
      decoration: BoxDecoration(
        color: featured ? t.primary : t.surface,
        borderRadius: radius,
        border: Border.all(
          color: selected && !featured ? t.signal : Colors.transparent,
          width: 2,
        ),
        boxShadow: featured ? t.primaryGlow : t.cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.all(featured ? Skyline.s20 : Skyline.s16),
            child: content,
          ),
        ),
      ),
    );
  }
}
