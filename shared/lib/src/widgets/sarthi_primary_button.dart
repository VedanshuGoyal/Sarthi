import 'package:flutter/material.dart';

/// The primary call-to-action button shared across both apps.
///
/// It is a thin, state-free wrapper over [FilledButton] that adds a busy
/// state: when [isLoading] is true it shows a spinner and ignores taps. It
/// renders only — the parent owns the loading flag and the [onPressed]
/// behaviour.
class SarthiPrimaryButton extends StatelessWidget {
  const SarthiPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  /// Text shown on the button.
  final String label;

  /// Tap callback. When null (or when [isLoading]) the button is disabled.
  final VoidCallback? onPressed;

  /// When true the button shows a spinner and cannot be tapped.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                // Match the button's foreground so the spinner stays visible on
                // the filled surface in every theme (a hardcoded white vanished
                // on Deep Signal's near-white dark-mode button).
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : Text(label),
    );
  }
}
