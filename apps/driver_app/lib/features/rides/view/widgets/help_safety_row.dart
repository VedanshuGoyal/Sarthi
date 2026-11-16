import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config_providers.dart';
import '../../../auth/driver_auth_controller.dart';
import '../../domain/ride.dart';
import '../ride_format.dart';
import 'ride_widgets.dart';

/// Opens [uri] outside the app (dialer, WhatsApp); false when nothing could.
typedef UriLauncher = Future<bool> Function(Uri uri);

/// Puts [text] on the clipboard.
typedef TextCopier = Future<void> Function(String text);

Future<bool> _launchExternally(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

Future<void> _copyToClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/// The texts and links behind the Help & safety row. Pure functions of
/// their inputs.
abstract final class HelpSafety {
  /// India's single emergency number.
  static final Uri emergencyCall = Uri(scheme: 'tel', path: '112');

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "Ravi" out of "Ravi Kumar"; empty for a blank name.
  static String firstName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.first;
  }

  /// The first 8 characters of a booking id, upper-cased: enough to tell
  /// rides apart in a message.
  static String shortId(String id) =>
      (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();

  /// "Mon, 26 Oct 2026, 9:00 AM" — absolute, since whoever reads a shared
  /// trip may read it on another day.
  static String dateTime(DateTime t) =>
      '${_weekdays[t.weekday - 1]}, ${t.day} ${_months[t.month - 1]} '
      '${t.year}, ${RideFormat.time(t)}';

  /// What "Share trip" sends: when, where from, who is driving and the
  /// booking. The driver's first name is left out when unknown.
  static String shareText(Ride ride, {String? driverFirstName}) {
    final name = driverFirstName?.trim() ?? '';
    return [
      "I'm driving a MOJUD trip.",
      'When: ${dateTime(ride.scheduledAt)}',
      'Pickup: ${ride.pickup.shortName}',
      if (name.isNotEmpty) 'Driver: $name',
      'Booking: ${shortId(ride.id)}',
    ].join('\n');
  }

  /// WhatsApp's share link: pick a chat, with [text] filled in.
  static Uri shareLink(String text) =>
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');

  /// A WhatsApp chat with MOJUD support about booking [rideId], or null
  /// when [supportPhone] has no digits.
  static Uri? supportLink(String? supportPhone, String rideId) {
    final digits = (supportPhone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    final text = Uri.encodeComponent('Booking $rideId');
    return Uri.parse('https://wa.me/$digits?text=$text');
  }
}

/// The Help & safety card on a ride the driver holds: call 112, share the
/// trip, and (when a support number is configured) message MOJUD support.
///
/// Reads the support number and the driver's name from their providers and
/// hands them to [HelpSafetyRow]; shows nothing for an open request.
class RideHelpSafety extends ConsumerWidget {
  const RideHelpSafety({super.key, required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ride.status == RideStatus.requested) return const SizedBox.shrink();
    final supportPhone = ref.watch(supportPhoneProvider).valueOrNull;
    final driverName = ref.watch(
      driverAuthControllerProvider.select((s) => s.valueOrNull?.driver.name),
    );
    return Padding(
      padding: const EdgeInsets.only(top: Skyline.s16),
      child: HelpSafetyRow(
        ride: ride,
        supportPhone: supportPhone,
        driverFirstName: driverName == null
            ? null
            : HelpSafety.firstName(driverName),
      ),
    );
  }
}

/// Three quick actions in a card. Renders what it's given and launches
/// through [launch] / [copy], so it can be shown and tested without a phone.
class HelpSafetyRow extends StatelessWidget {
  const HelpSafetyRow({
    super.key,
    required this.ride,
    this.supportPhone,
    this.driverFirstName,
    this.launch = _launchExternally,
    this.copy = _copyToClipboard,
  });

  final Ride ride;

  /// MOJUD support's number; null hides "Contact support".
  final String? supportPhone;
  final String? driverFirstName;
  final UriLauncher launch;
  final TextCopier copy;

  Future<void> _callEmergency(BuildContext context) async {
    final ok = await launch(HelpSafety.emergencyCall);
    if (!ok && context.mounted) {
      _say(context, "Couldn't open the dialer. Dial 112.");
    }
  }

  Future<void> _shareTrip(BuildContext context) async {
    final text = HelpSafety.shareText(ride, driverFirstName: driverFirstName);
    if (await launch(HelpSafety.shareLink(text))) return;
    await copy(text);
    if (context.mounted) _say(context, 'Trip details copied');
  }

  Future<void> _contactSupport(BuildContext context, Uri link) async {
    final ok = await launch(link);
    if (!ok && context.mounted) {
      _say(context, "Couldn't open WhatsApp on this phone.");
    }
  }

  static void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final support = HelpSafety.supportLink(supportPhone, ride.id);
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Help & safety'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _HelpAction(
                  icon: Icons.sos_rounded,
                  label: 'Call 112',
                  background: t.danger.withValues(alpha: 0.12),
                  foreground: t.danger,
                  onTap: () => _callEmergency(context),
                ),
              ),
              Expanded(
                child: _HelpAction(
                  icon: Icons.share_rounded,
                  label: 'Share trip',
                  background: t.primarySoft,
                  foreground: t.primaryText,
                  onTap: () => _shareTrip(context),
                ),
              ),
              if (support != null)
                Expanded(
                  child: _HelpAction(
                    icon: Icons.support_agent_rounded,
                    label: 'Contact support',
                    background: t.primarySoft,
                    foreground: t.primaryText,
                    onTap: () => _contactSupport(context, support),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A round icon with its label under it; the whole column is the tap target.
class _HelpAction extends StatelessWidget {
  const _HelpAction({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Skyline.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Skyline.s4,
            vertical: Skyline.s8,
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: foreground, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: t.label(size: 12.5, color: t.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
