import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] outside the app; true if something took it.
typedef UrlOpener = Future<bool> Function(Uri url);

Future<bool> _openExternally(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// The full-screen "Update MOJUD" page, shown in place of the whole app once
/// the backend stops serving this build. There is no way past it: the only
/// way on is installing the new build from [downloadUrl].
///
/// A pure view: it renders the URL, opens it through [openUrl], and offers
/// the link to copy in case no browser takes it.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.downloadUrl,
    this.openUrl = _openExternally,
  });

  final String downloadUrl;
  final UrlOpener openUrl;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _openFailed = false;
  bool _copied = false;

  Future<void> _open() async {
    final uri = Uri.tryParse(widget.downloadUrl);
    var ok = false;
    if (uri != null) {
      try {
        ok = await widget.openUrl(uri);
      } catch (_) {
        ok = false;
      }
    }
    if (mounted) setState(() => _openFailed = !ok);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.downloadUrl));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final site = widget.downloadUrl
        .replaceFirst(RegExp('^https?://'), '')
        .replaceFirst(RegExp(r'/$'), '');

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Skyline.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(Skyline.s20),
                      decoration: BoxDecoration(
                        color: t.primarySoft,
                        borderRadius: BorderRadius.circular(Skyline.radiusLg),
                      ),
                      child: Icon(
                        Icons.system_update_rounded,
                        size: 48,
                        color: t.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: Skyline.s32),
                  Text(
                    'Update MOJUD',
                    textAlign: TextAlign.center,
                    style: t.heading(28),
                  ),
                  const SizedBox(height: Skyline.s12),
                  Text(
                    'This version of the app is out of date. Install the '
                    'latest one to keep booking drivers. Your account and '
                    'rides are safe.',
                    textAlign: TextAlign.center,
                    style: t.body(size: 15),
                  ),
                  const SizedBox(height: Skyline.s32),
                  SarthiPrimaryButton(
                    label: 'Get the latest version',
                    onPressed: _open,
                  ),
                  const SizedBox(height: Skyline.s16),
                  Text(
                    _openFailed
                        ? "Couldn't open a browser. Copy the link and open "
                              'it in one: $site'
                        : 'Download it from $site',
                    textAlign: TextAlign.center,
                    style: t.label(color: _openFailed ? t.danger : t.inkMuted),
                  ),
                  const SizedBox(height: Skyline.s4),
                  Center(
                    child: TextButton.icon(
                      onPressed: _copy,
                      icon: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 18,
                      ),
                      label: Text(_copied ? 'Link copied' : 'Copy link'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
