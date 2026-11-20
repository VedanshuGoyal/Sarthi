import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/legal.dart';
import '../../../l10n/l10n.dart';

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
    final l10n = context.l10n;
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
                    // The sentence's word order is the language's: split it
                    // at the two links rather than gluing pieces together.
                    for (final part in _consentParts(
                      l10n.consentAgree(_termsMark, _privacyMark),
                    ))
                      switch (part) {
                        _termsMark => TextSpan(
                          text: l10n.consentTerms,
                          style: link,
                          recognizer: _terms,
                        ),
                        _privacyMark => TextSpan(
                          text: l10n.consentPrivacy,
                          style: link,
                          recognizer: _privacy,
                        ),
                        _ => TextSpan(text: part),
                      },
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

/// Stand-ins for the two links while splitting the consent sentence.
const String _termsMark = '\u0001';
const String _privacyMark = '\u0002';

/// The consent sentence cut into plain runs and the [_termsMark] /
/// [_privacyMark] markers, in order, without empty runs.
List<String> _consentParts(String sentence) => [
  for (final part in sentence.split(
    RegExp('(?=[\u0001\u0002])|(?<=[\u0001\u0002])'),
  ))
    if (part.isNotEmpty) part,
];
