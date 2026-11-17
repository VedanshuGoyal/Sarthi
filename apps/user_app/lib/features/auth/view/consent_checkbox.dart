import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/legal.dart';

/// Opens a legal document; returns whether it could.
typedef LinkOpener = Future<bool> Function(Uri url);

Future<bool> _openExternally(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// "I agree to the Terms and Privacy Policy": a checkbox the customer must
/// tick to create an account, with both documents as tappable links.
///
/// Renders [value] and reports taps through [onChanged]; [errorText] shows
/// under it when the customer tries to continue without agreeing.
class ConsentCheckbox extends StatefulWidget {
  const ConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
    this.openLink = _openExternally,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? errorText;

  /// How a link is opened; tests pass a fake.
  final LinkOpener openLink;

  @override
  State<ConsentCheckbox> createState() => _ConsentCheckboxState();
}

class _ConsentCheckboxState extends State<ConsentCheckbox> {
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => widget.openLink(Legal.termsUrl);
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => widget.openLink(Legal.privacyUrl);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = TextStyle(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    final onChanged = widget.onChanged;
    final error = widget.errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Checkbox(
              value: widget.value,
              onChanged: onChanged == null
                  ? null
                  : (checked) => onChanged(checked ?? false),
              isError: error != null,
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    TextSpan(text: 'Terms', style: link, recognizer: _terms),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: link,
                      recognizer: _privacy,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
