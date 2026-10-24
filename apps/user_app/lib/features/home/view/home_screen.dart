import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/mojud_logo.dart';
import '../../auth/auth_controller.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_user.dart';
import '../../profile/view/profile_screen.dart';
import '../../profile/view/widgets/user_avatar.dart';
import '../../ride/data/booking_repository.dart';
import '../../ride/domain/multi_stop_trip.dart';
import '../../ride/domain/one_way_trip.dart';
import '../../ride/domain/pickup_location.dart';
import '../../ride/domain/round_trip_booking.dart';
import '../../ride/domain/trip_type.dart';
import '../../ride/ride_providers.dart';
import '../../ride/view/booking_details_screen.dart';
import '../../ride/view/multi_stop_planner_screen.dart';
import '../../ride/view/one_way_details_screen.dart';
import '../../ride/view/pickup_location_screen.dart';
import '../../ride/view/trip_type_selector.dart';
import '../../ride/view/widgets/ride_theme.dart';
import '../../../core/theme/skyline/skyline_tokens.dart';

/// Landing screen shown after a customer finishes registering.
///
/// Greets the user, then hosts the [TripTypeSelector] so they can pick how they
/// want to travel, above a short "how it works" card. The body is centred and
/// width-capped on large screens and scrolls on short ones, per the
/// responsive-layout guideline.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.user});

  final AuthUser user;

  /// Revokes the session on the server (best-effort), then wipes it from memory
  /// and secure storage — returning the app to onboarding.
  Future<void> _logout(WidgetRef ref) async {
    final auth = ref.read(authControllerProvider.notifier);
    final token = auth.token;
    if (token != null) {
      try {
        await ref.read(authRepositoryProvider).logout(token);
      } catch (_) {
        // Already clearing locally; a failed server revoke shouldn't block it.
      }
    }
    await auth.signOut();
  }

  /// Opens the account page. Logging out from it pops back here first, so the
  /// root swap to onboarding isn't hidden under a stale profile route.
  void _openProfile(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          user: user,
          onLogout: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
            _logout(ref);
          },
        ),
      ),
    );
  }

  /// Sends the confirmed booking to the backend right away so the server has
  /// its details on record. Returns whether the server acknowledged it; a
  /// failure only annotates the confirmation, it never blocks it.
  Future<bool> _sendToServer(
    WidgetRef ref,
    Future<void> Function(BookingRepository repo) send,
  ) async {
    try {
      await send(ref.read(bookingRepositoryProvider));
      return true;
    } on BookingSubmitException {
      return false;
    }
  }

  /// The snackbar tail noting a booking that didn't reach the backend.
  static const String _notSentNote = " We couldn't reach the server.";

  /// Routes the tapped trip choice to its next step. Round Trip advances to
  /// the pickup-location step, then the booking-details step; Multi-Stop to the
  /// starting-point step, then the trip planner; One-Way to the starting-point
  /// step, the destination step, then the details step.
  Future<void> _onTripSelected(
    BuildContext context,
    WidgetRef ref,
    TripType type,
  ) async {
    switch (type) {
      case TripType.roundTrip:
        final pickup = await Navigator.of(context).push<PickupLocation>(
          MaterialPageRoute(builder: (_) => const PickupLocationScreen()),
        );
        if (pickup == null || !context.mounted) return;
        final booking = await Navigator.of(context).push<RoundTripBooking>(
          MaterialPageRoute(
            builder: (_) => BookingDetailsScreen(pickup: pickup),
          ),
        );
        if (booking != null && context.mounted) {
          final sent = await _sendToServer(
            ref,
            (repo) => repo.submitRoundTrip(booking),
          );
          if (!context.mounted) return;
          final hours = booking.hours;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Round Trip booked: $hours ${hours == 1 ? 'hour' : 'hours'}, '
                  'in your ${booking.car.registration}.'
                  '${sent ? '' : _notSentNote}',
                ),
              ),
            );
        }
      case TripType.multiStop:
        final start = await Navigator.of(context).push<PickupLocation>(
          MaterialPageRoute(
            builder: (_) => const PickupLocationScreen(
              title: 'Set starting point',
              fieldLabel: 'Starting point',
            ),
          ),
        );
        if (start == null || !context.mounted) return;
        final trip = await Navigator.of(context).push<MultiStopTrip>(
          MaterialPageRoute(
            builder: (_) => MultiStopPlannerScreen(start: start),
          ),
        );
        if (trip != null && context.mounted) {
          final sent = await _sendToServer(
            ref,
            (repo) => repo.submitMultiStop(trip),
          );
          if (!context.mounted) return;
          final count = trip.stops.length;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Multi-Stop trip booked: $count '
                  '${count == 1 ? 'stop' : 'stops'} planned.'
                  '${sent ? '' : _notSentNote}',
                ),
              ),
            );
        }
      case TripType.oneWay:
        final start = await Navigator.of(context).push<PickupLocation>(
          MaterialPageRoute(
            builder: (_) => const PickupLocationScreen(
              title: 'Set starting point',
              fieldLabel: 'Starting point',
            ),
          ),
        );
        if (start == null || !context.mounted) return;
        // Both steps share the auto-disposing pickup view model, and the second
        // push overlaps the first screen's pop animation — invalidate so the
        // destination step doesn't inherit the starting point as its selection.
        ref.invalidate(pickupSelectionViewModelProvider);
        final destination = await Navigator.of(context).push<PickupLocation>(
          MaterialPageRoute(
            builder: (_) => const PickupLocationScreen(
              title: 'Set destination',
              fieldLabel: 'Destination',
            ),
          ),
        );
        if (destination == null || !context.mounted) return;
        final trip = await Navigator.of(context).push<OneWayTrip>(
          MaterialPageRoute(
            builder: (_) =>
                OneWayDetailsScreen(start: start, destination: destination),
          ),
        );
        if (trip != null && context.mounted) {
          final sent = await _sendToServer(
            ref,
            (repo) => repo.submitOneWay(trip),
          );
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'One-Way Trip booked: ~${trip.estimatedTravelTime.inMinutes}'
                  ' min, in your ${trip.car.registration} '
                  'to ${trip.destination.address}.'
                  '${sent ? '' : _notSentNote}',
                ),
              ),
            );
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = user.name.split(' ').first;
    final t = SkylineTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Theme(
      // The ride wash (selected tints, info panels) comes from the app theme.
      data: rideSurfaceTheme(context),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: Skyline.s20,
          title: const MojudLockup(markHeight: 22),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: Skyline.s12),
              child: IconButton(
                icon: UserAvatar(name: user.name, radius: 17),
                tooltip: 'Your profile',
                onPressed: () => _openProfile(context, ref),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Skyline.s20,
                  Skyline.s8,
                  Skyline.s20,
                  Skyline.s32,
                ),
                children: [
                  Text('Hello, $firstName', style: t.body(size: 15)),
                  const SizedBox(height: Skyline.s4),
                  Text(
                    'Where should we drive you today?',
                    style: text.headlineMedium,
                  ),
                  const SizedBox(height: Skyline.s24),
                  Text('Book a driver', style: t.title(16)),
                  const SizedBox(height: Skyline.s12),
                  TripTypeSelector(
                    onSelected: (type) => _onTripSelected(context, ref, type),
                  ),
                  const SizedBox(height: Skyline.s24),
                  const _HowItWorks(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Your car, our driver" — the service promise and its three steps, so a
/// first-time customer knows what booking leads to.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = <(IconData, String)>[
    (Icons.touch_app_rounded, 'Pick a trip'),
    (Icons.place_rounded, 'Set pickup & time'),
    (Icons.directions_car_rounded, 'Driver drives your car'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Skyline.s20),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(Skyline.radiusLg),
        boxShadow: t.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your car, our driver', style: t.title(16)),
          const SizedBox(height: Skyline.s4),
          Text(
            'A driver comes to your pickup and drives your own car.',
            style: t.body(size: 13),
          ),
          const SizedBox(height: Skyline.s16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, (icon, label)) in _steps.indexed) ...[
                if (i > 0) const SizedBox(width: Skyline.s8),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: t.primarySoft,
                          borderRadius: BorderRadius.circular(Skyline.radiusSm),
                        ),
                        child: Icon(icon, color: t.primaryText, size: 22),
                      ),
                      const SizedBox(height: Skyline.s8),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: t.label(size: 12, color: t.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
