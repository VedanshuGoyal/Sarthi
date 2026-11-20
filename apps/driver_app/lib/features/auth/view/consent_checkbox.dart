import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/legal.dart';
import '../../../l10n/l10n.dart';

/// Opens a legal document; false when nothing could open it.
typedef LinkOpener = Future<bool> Function(Uri uri);

Future<bool> _openInBrowser(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// "I agree to the Terms and Privacy Policy", with both names linking to
/// the documents on apps.mojud.life. Renders [value] and reports taps
/// through [onChanged]; the view model owns whether the box is ticked.
class ConsentCheckbox extends StatelessWidget {
  const ConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.openLink = _openInBrowser,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final LinkOpener openLink;

  Future<void> _open(BuildContext context, Uri uri) async {
    if (await openLink(uri)) return;
    if (!context.mounted) return;
    // No browser: show the address so the driver can open it themselves.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.consentOpenInBrowser('${uri.host}${uri.path}'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final text = t.body(size: 13.5, color: t.inkMuted);
    final link = t
        .label(size: 13.5, color: t.primaryText)
        .copyWith(decoration: TextDecoration.underline);
    void toggle() {
      if (enabled) onChanged(!value);
    }

    Widget plain(String s) => GestureDetector(
      onTap: toggle,
      child: Text(s, style: text),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: value,
          onChanged: enabled ? (v) => onChanged(v ?? false) : null,
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // The sentence's word order is the language's: split it at
              // the two links rather than gluing English pieces together.
              for (final part in _consentParts(
                l10n.consentAgree(_terms, _privacy),
              ))
                switch (part) {
                  _terms => InkWell(
                    onTap: () => _open(context, Legal.termsUrl),
                    child: Text(l10n.consentTerms, style: link),
                  ),
                  _privacy => InkWell(
                    onTap: () => _open(context, Legal.privacyUrl),
                    child: Text(l10n.consentPrivacy, style: link),
                  ),
                  _ => plain(part),
                },
            ],
          ),
        ),
      ],
    );
  }
}

/// Stand-ins for the two links while splitting the consent sentence.
const String _terms = '\u0001';
const String _privacy = '\u0002';

/// The consent sentence cut into plain runs and the [_terms] / [_privacy]
/// markers, in order, without empty runs.
List<String> _consentParts(String sentence) => [
  for (final part in sentence.split(
    RegExp('(?=[\u0001\u0002])|(?<=[\u0001\u0002])'),
  ))
    if (part.isNotEmpty) part,
];
