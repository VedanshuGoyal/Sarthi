import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/my_booking.dart';
import '../../help_safety_providers.dart';

/// Opens [uri] in another app (dialer, WhatsApp); false when nothing could.
typedef UriLauncher = Future<bool> Function(Uri uri);

/// Puts [text] on the clipboard.
typedef TextCopier = Future<void> Function(String text);

Future<bool> _launch(Uri uri) => launchUrl(
  uri,
  mode: uri.scheme == 'tel'
      ? LaunchMode.platformDefault
      : LaunchMode.externalApplication,
);

Future<void> _copy(String text) => Clipboard.setData(ClipboardData(text: text));

/// The words and links behind "Help & safety", kept free of widgets so they
/// can be tested on their own.
abstract final class HelpSafety {
  /// India's emergency number, in the phone's dialer.
  static final Uri sosUri = Uri(scheme: 'tel', path: '112');

  /// What "Share trip" sends a friend: when, where from, who's driving and
  /// the booking, e.g.
  ///
  ///     My MOJUD trip
  ///     When: Wed 18 Nov, 9:30 AM
  ///     Pickup: Indiranagar, Bengaluru
  ///     Driver: Ravi
  ///     Booking: 3F2A9C1B
  static String shareText(MyBooking booking) {
    final driver = booking.driverFirstName;
    return [
      'My MOJUD trip',
      'When: ${formatWhen(booking.scheduledAt)}',
      'Pickup: ${booking.pickupAddress}',
      if (driver != null) 'Driver: $driver',
      'Booking: ${shortId(booking.id)}',
    ].join('\n');
  }

  /// A WhatsApp share of [text], where the customer picks who gets it.
  static Uri shareUri(String text) =>
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');

  /// A WhatsApp chat with MOJUD support at [phone], opening on the booking.
  static Uri supportUri(String phone, String bookingId) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final text = Uri.encodeComponent('Booking $bookingId');
    return Uri.parse('https://wa.me/$digits?text=$text');
  }

  /// The first eight characters of a booking id, upper-cased: enough to
  /// tell a friend which ride, short enough to read out.
  static String shortId(String id) =>
      (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();

  /// "Wed 18 Nov, 9:30 AM", without a locale (the text leaves the app).
  static String formatWhen(DateTime at) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');
    final half = at.hour < 12 ? 'AM' : 'PM';
    return '${days[at.weekday - 1]} ${at.day} ${months[at.month - 1]}, '
        '$hour:$minute $half';
  }
}

/// [HelpSafetyRow] for [booking], with the support number from
/// [supportPhoneProvider] (hidden until it's known, and when there's none).
class RideHelpSafety extends ConsumerWidget {
  const RideHelpSafety({super.key, required this.booking});

  final MyBooking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = ref.watch(supportPhoneProvider).valueOrNull;
    return HelpSafetyRow(booking: booking, supportPhone: phone);
  }
}

/// "Help & safety" on a ride: call 112 and share the trip while the ride is
/// still ahead or under way, and contact MOJUD support on WhatsApp when
/// there's a [supportPhone]. Renders nothing when none of them applies.
class HelpSafetyRow extends StatelessWidget {
  const HelpSafetyRow({
    super.key,
    required this.booking,
    this.supportPhone,
    this.launch = _launch,
    this.copy = _copy,
  });

  final MyBooking booking;
  final String? supportPhone;

  /// How links are opened and text copied; tests pass fakes.
  final UriLauncher launch;
  final TextCopier copy;

  Future<bool> _open(Uri uri) async {
    try {
      return await launch(uri);
    } catch (_) {
      return false;
    }
  }

  void _say(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _callSos(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _open(HelpSafety.sosUri)) {
      _say(messenger, "Couldn't open the dialer. Dial 112.");
    }
  }

  /// WhatsApp when the phone has it; otherwise the text is copied to paste
  /// anywhere.
  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = HelpSafety.shareText(booking);
    if (await _open(HelpSafety.shareUri(text))) return;
    await copy(text);
    _say(messenger, 'Trip details copied');
  }

  Future<void> _contactSupport(BuildContext context, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _open(HelpSafety.supportUri(phone, booking.id))) {
      _say(messenger, "Couldn't open WhatsApp.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final ongoing = booking.status.isActive;
    final phone = supportPhone;
    final buttons = <Widget>[
      if (ongoing)
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: t.danger,
            side: BorderSide(color: t.danger.withValues(alpha: 0.35)),
          ),
          onPressed: () => _callSos(context),
          icon: const Icon(Icons.sos_rounded),
          label: const Text('Call 112'),
        ),
      if (ongoing)
        OutlinedButton.icon(
          onPressed: () => _share(context),
          icon: const Icon(Icons.share_rounded),
          label: const Text('Share trip'),
        ),
      if (phone != null)
        OutlinedButton.icon(
          onPressed: () => _contactSupport(context, phone),
          icon: const Icon(Icons.support_agent_rounded),
          label: const Text('Contact support'),
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();
    return SkylineSection(
      title: 'Help & safety',
      child: Wrap(
        spacing: Skyline.s8,
        runSpacing: Skyline.s8,
        children: buttons,
      ),
    );
  }
}
