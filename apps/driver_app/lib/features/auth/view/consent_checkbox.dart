import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/legal.dart';

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
      SnackBar(content: Text('Open ${uri.host}${uri.path} in a browser')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final text = t.body(size: 13.5, color: t.inkMuted);
    final link = t
        .label(size: 13.5, color: t.primaryText)
        .copyWith(decoration: TextDecoration.underline);
    void toggle() {
      if (enabled) onChanged(!value);
    }

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
              GestureDetector(
                onTap: toggle,
                child: Text('I agree to the ', style: text),
              ),
              InkWell(
                onTap: () => _open(context, Legal.termsUrl),
                child: Text('Terms', style: link),
              ),
              GestureDetector(
                onTap: toggle,
                child: Text(' and ', style: text),
              ),
              InkWell(
                onTap: () => _open(context, Legal.privacyUrl),
                child: Text('Privacy Policy', style: link),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
