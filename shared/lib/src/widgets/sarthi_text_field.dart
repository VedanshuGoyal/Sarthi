import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A labelled text field used throughout Sarthi forms.
///
/// State-free: the parent owns the [controller] and reacts to [onChanged] /
/// [onSubmitted]. It standardises the label, hint, keyboard, and error styling
/// so every form in both apps looks identical.
class SarthiTextField extends StatelessWidget {
  const SarthiTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.autofocus = false,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  /// When non-null, shown in the error colour beneath the field.
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool autofocus;

  /// When true the field can't be typed into — pair with [onTap] for
  /// picker-style fields (e.g. a date of birth that opens a calendar).
  final bool readOnly;

  /// Line bounds for multiline fields (e.g. a free-text note). Defaults to the
  /// single-line behaviour of a plain [TextField].
  final int? maxLines;
  final int? minLines;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          autofocus: autofocus,
          readOnly: readOnly,
          maxLines: maxLines,
          minLines: minLines,
          onTap: onTap,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            suffixIcon: suffixIcon,
            prefixIcon: prefixIcon,
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}
