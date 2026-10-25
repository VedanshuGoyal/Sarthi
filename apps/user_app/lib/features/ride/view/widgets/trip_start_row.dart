import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../domain/pickup_location.dart';

/// The "From" row on top of the One-Way route step (and Round Trip's pickup
/// row): the starting point, filled from GPS, tappable to change.
///
/// Render-only: shows [start] (or a locating / "choose one" state) and emits
/// [onTap]. The parent owns the GPS call and the picker.
class TripStartRow extends StatelessWidget {
  const TripStartRow({
    super.key,
    required this.start,
    required this.isLocating,
    this.isCurrentLocation = false,
    this.label = 'Starting point',
    this.onTap,
  });

  /// The chosen starting point; null while locating or when GPS failed.
  final PickupLocation? start;
  final bool isLocating;

  /// Whether [start] came from GPS, so the row can say so.
  final bool isCurrentLocation;

  /// What the place is called on this step — "Starting point", "Pickup".
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final start = this.start;
    final (title, subtitle) = switch ((start, isLocating)) {
      (final s?, _) => (
        s.address,
        isCurrentLocation
            ? 'From your current location · tap to change'
            : '$label · tap to change',
      ),
      (null, true) => ('Finding your location…', label),
      (null, false) => (
        'Choose a ${label.toLowerCase()}',
        "Couldn't use your current location",
      ),
    };
    return SkylineRow(
      icon: Icons.trip_origin_rounded,
      title: title,
      subtitle: subtitle,
      // Only an action while there's nothing to show yet.
      accent: start == null,
      leading: isLocating && start == null
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : null,
      trailing: Icon(Icons.edit_location_alt_outlined, color: t.inkMuted),
      onTap: onTap,
    );
  }
}
