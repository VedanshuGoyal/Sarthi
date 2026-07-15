import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/sarthi_colors.dart';

/// A phone-number entry field with a fixed `+91` (India) country prefix.
///
/// Sarthi currently onboards only Indian numbers, so the country code is shown
/// as a non-editable prefix and the user types the 10-digit national number.
/// Input is restricted to digits and capped at 10 characters. The widget is
/// state-free: it surfaces the typed digits through [onChanged] and reports an
/// optional [errorText] supplied by the parent.
class SarthiPhoneField extends StatelessWidget {
  const SarthiPhoneField({
    super.key,
    this.controller,
    this.errorText,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  /// Country dialling code rendered as the immovable prefix.
  static const String countryCode = '+91';

  /// Number of national-significant digits expected for an Indian mobile.
  static const int nationalDigits = 10;

  final TextEditingController? controller;
  final String? errorText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mobile number',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(nationalDigits),
          ],
          decoration: InputDecoration(
            hintText: '98765 43210',
            errorText: errorText,
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    countryCode,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: SarthiColors.ultramarine,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(width: 1, height: 24, color: theme.dividerColor),
                ],
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
          ),
        ),
      ],
    );
  }
}
