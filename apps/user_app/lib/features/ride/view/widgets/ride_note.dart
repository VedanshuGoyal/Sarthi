import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// A calm note about a ride or a booking — money owed on earlier rides,
/// running past the booked time: an icon and [text] on a pale wash.
/// Renders data only.
class RideNote extends StatelessWidget {
  const RideNote({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Skyline.s12,
        vertical: Skyline.s8,
      ),
      decoration: BoxDecoration(
        color: t.isDark ? t.sunken : t.primarySoft,
        borderRadius: BorderRadius.circular(Skyline.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: t.primaryText),
          ),
          const SizedBox(width: Skyline.s8),
          Expanded(
            child: Text(text, style: t.body(size: 13, color: t.ink)),
          ),
        ],
      ),
    );
  }
}
