import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../../l10n/l10n.dart';
import '../../domain/pickup_location.dart';

/// What the start of a trip is called on a step: the "Starting point" of a
/// One-Way route, or Round Trip's "Pickup".
enum TripStartKind { startingPoint, pickup }

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
    this.kind = TripStartKind.startingPoint,
    this.onTap,
  });

  /// The chosen starting point; null while locating or when GPS failed.
  final PickupLocation? start;
  final bool isLocating;

  /// Whether [start] came from GPS, so the row can say so.
  final bool isCurrentLocation;

  /// What the place is called on this step — "Starting point", "Pickup".
  final TripStartKind kind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final start = this.start;
    final pickup = kind == TripStartKind.pickup;
    final (title, subtitle) = switch ((start, isLocating)) {
      (final s?, _) => (
        s.address,
        isCurrentLocation
            ? l10n.tripStartFromCurrentLocation
            : pickup
            ? l10n.tripStartPickupTapToChange
            : l10n.tripStartStartingPointTapToChange,
      ),
      (null, true) => (
        l10n.tripStartFindingLocation,
        pickup ? l10n.tripStartPickup : l10n.tripStartStartingPoint,
      ),
      (null, false) => (
        pickup ? l10n.tripStartChoosePickup : l10n.tripStartChooseStartingPoint,
        l10n.tripStartNoCurrentLocation,
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
