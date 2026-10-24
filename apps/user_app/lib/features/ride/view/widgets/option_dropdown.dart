import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// A labelled dropdown for a small fixed set of choices.
///
/// State-free per the reusable-widget guideline: it renders [value] (or the
/// [hintText] placeholder) and emits [onChanged]; the parent owns the choice.
/// Styled like [SarthiTextField] — label above a bordered field — so dropdowns
/// sit naturally next to text fields in a form.
class OptionDropdown<T> extends StatelessWidget {
  const OptionDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hintText,
  });

  final String label;
  final T? value;

  /// The choices in display order, each with its user-facing name.
  final List<(T, String)> options;

  final ValueChanged<T> onChanged;

  /// Shown in the field until a [value] is chosen.
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          ),
          isEmpty: value == null,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(Skyline.radius),
              hint: hintText == null ? null : Text(hintText!),
              items: [
                for (final (option, name) in options)
                  DropdownMenuItem(value: option, child: Text(name)),
              ],
              onChanged: (picked) {
                if (picked != null) onChanged(picked);
              },
            ),
          ),
        ),
      ],
    );
  }
}
