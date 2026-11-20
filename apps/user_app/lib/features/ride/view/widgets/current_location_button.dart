import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../../l10n/l10n.dart';

/// "Use my current location" action for the pickup step — opens the map picker
/// on the GPS fix, or resolves GPS directly when there's no map.
///
/// Render-only: shows a spinner while [isBusy] and emits [onPressed]. The
/// parent owns the busy flag and the GPS call.
class CurrentLocationButton extends StatelessWidget {
  const CurrentLocationButton({
    super.key,
    required this.onPressed,
    this.isBusy = false,
    this.subtitle,
  });

  final VoidCallback onPressed;
  final bool isBusy;

  /// Optional hint under the title, e.g. that the row opens the map.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return SkylineRow(
      icon: Icons.my_location_rounded,
      title: context.l10n.locationUseCurrent,
      subtitle: subtitle,
      accent: true,
      leading: isBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : null,
      onTap: isBusy ? null : onPressed,
    );
  }
}
