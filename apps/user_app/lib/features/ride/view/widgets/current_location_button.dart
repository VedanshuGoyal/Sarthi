import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: isBusy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Icon(Icons.my_location, color: theme.colorScheme.primary),
      title: Text(
        'Use my current location',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: isBusy ? null : onPressed,
    );
  }
}
