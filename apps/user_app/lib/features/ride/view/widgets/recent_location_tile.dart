import 'package:flutter/material.dart';

import '../../domain/pickup_location.dart';
import '../../../../core/theme/skyline/skyline_row.dart';

/// A tappable past pickup shown when the search field is empty.
///
/// Render-only: shows a saved [location] and reports taps through [onTap].
/// Selecting one reuses its stored coordinates, so it costs no Ola request.
class RecentLocationTile extends StatelessWidget {
  const RecentLocationTile({
    super.key,
    required this.location,
    required this.onTap,
  });

  final PickupLocation location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SkylineRow(
      icon: Icons.history_rounded,
      title: location.address,
      onTap: onTap,
    );
  }
}
