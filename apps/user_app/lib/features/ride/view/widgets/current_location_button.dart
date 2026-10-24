import 'package:flutter/material.dart';
import '../../../../core/theme/skyline/skyline_row.dart';

/// "Use my current location" action for the pickup step.
///
/// Render-only: shows a spinner while [isBusy] and emits [onPressed]. The
/// parent owns the busy flag and the GPS call.
class CurrentLocationButton extends StatelessWidget {
  const CurrentLocationButton({
    super.key,
    required this.onPressed,
    this.isBusy = false,
  });

  final VoidCallback onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return SkylineRow(
      icon: Icons.my_location_rounded,
      title: 'Use my current location',
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
