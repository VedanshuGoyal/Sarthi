import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/mojud_logo.dart';
import '../../../l10n/l10n.dart';
import '../../auth/domain/auth_user.dart';
import '../../profile/view/widgets/user_avatar.dart';
import '../../ride/data/booking_repository.dart';
import '../../ride/domain/multi_stop_trip.dart';
import '../../ride/domain/one_way_trip.dart';
import '../../ride/domain/pickup_location.dart';
import '../../ride/domain/round_trip_booking.dart';
import '../../ride/domain/trip_type.dart';
import '../../ride/ride_providers.dart';
import '../../ride/view/activity_panel.dart';
import '../../ride/view/booking_details_screen.dart';
import '../../ride/view/multi_stop_planner_screen.dart';
import '../../ride/view/one_way_details_screen.dart';
import '../../ride/view/one_way_route_screen.dart';
import '../../ride/view/pickup_location_screen.dart';
import '../../ride/view/trip_type_selector.dart';
import '../../ride/view/widgets/ride_format.dart';
import '../../ride/view/widgets/ride_theme.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// The Home tab of [UserHomeShell], shown after a customer signs in.
///
/// Greets the user, then hosts the [TripTypeSelector] so they can pick how
/// they want to travel, above a short "how it works" card. Their bookings
/// live in the Activity tab. The body is centred and
/// width-capped on large screens and scrolls on short ones, per the
/// responsive-layout guideline.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.user, this.onOpenAccount});

  final AuthUser user;

  /// Invoked when the customer taps their avatar — the shell switches to the
  /// Account tab. When null the avatar is display-only.
  final VoidCallback? onOpenAccount;

  /// Sends the confirmed booking to the backend, then says how it went: the
  /// confirmation once the server has it; otherwise that nothing was booked,
  /// the server's reason, and a retry. A booking the server never took is
  /// no booking — no driver will see it — so it must never read as booked.
  ///
  /// [send] carries the attempt's idempotency key, so the retry re-sends the
  /// same attempt: if the first one did land, the server answers with that
  /// booking instead of making a second. An unpaid ride no longer stops a
  /// booking — the server adds what's owed to the next payment — but a
  /// refusal for one (`payment_due`, from servers before that) still offers
  /// to open that ride, where its Pay button is.
  ///
  /// [notBooked] words the failure for this trip type around the reason.
  Future<void> _book(
    BuildContext context,
    WidgetRef ref, {
    required String Function(String reason) notBooked,
    required String booked,
    required Future<void> Function(BookingRepository repo) send,
  }) async {
    BookingSubmitException? failure;
    try {
      await send(ref.read(bookingRepositoryProvider));
      // Show the new booking in Activity straight away.
      ref.read(myBookingsViewModelProvider).load();
    } on BookingSubmitException catch (e) {
      failure = e;
    }
    if (!context.mounted) return;
    final l10n = context.l10n;
    final String message;
    final SnackBarAction? action;
    if (failure == null) {
      (message, action) = (booked, null);
    } else if (failure.isPaymentDue) {
      final unpaid = failure.bookingId!;
      final owed = ref.read(myBookingsViewModelProvider).byId(unpaid);
      message = owed != null && owed.hasCancellationFee
          ? l10n.homePayFeeBeforeBooking(
              RideFormat.rupees(owed.cancellationFeePaise),
            )
          : failure.message;
      action = SnackBarAction(
        label: l10n.homePayNow,
        onPressed: () => _openUnpaidRide(context, ref, unpaid),
      );
    } else {
      message = notBooked(failure.message);
      action = SnackBarAction(
        label: l10n.homeRetry,
        onPressed: () {
          if (!context.mounted) return;
          _book(context, ref, notBooked: notBooked, booked: booked, send: send);
        },
      );
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  /// Opens the unpaid ride [bookingId] once the rides list has it — the
  /// details screen reads the ride from that list.
  Future<void> _openUnpaidRide(
    BuildContext context,
    WidgetRef ref,
    String bookingId,
  ) async {
    await ref.read(myBookingsViewModelProvider).load();
    if (!context.mounted) return;
    await openRideDetails(context, bookingId);
  }

  /// Routes the tapped trip choice to its next step. Round Trip opens the
  /// booking page (pickup pre-filled from GPS); Multi-Stop to the
  /// starting-point step, then the trip planner; One-Way to the route step
  /// (start pre-filled from GPS, destination to type), then the details step.
  Future<void> _onTripSelected(
    BuildContext context,
    WidgetRef ref,
    TripType type,
  ) async {
    final l10n = context.l10n;
    switch (type) {
      case TripType.roundTrip:
        // Straight to the booking page: the pickup is pre-filled from GPS
        // and tapped to change.
        final booking = await Navigator.of(context).push<RoundTripBooking>(
          MaterialPageRoute(builder: (_) => const BookingDetailsScreen()),
        );
        if (booking != null && context.mounted) {
          final hours = booking.hours;
          // One key per confirmed booking, kept across its retries.
          final key = newIdempotencyKey();
          await _book(
            context,
            ref,
            notBooked: l10n.homeNotBookedRoundTrip,
            booked: l10n.homeBookedRoundTrip(hours, booking.car.registration),
            send: (repo) => repo.submitRoundTrip(booking, idempotencyKey: key),
          );
        }
      case TripType.multiStop:
        final start = await Navigator.of(context).push<PickupLocation>(
          MaterialPageRoute(
            builder: (_) => PickupLocationScreen(
              title: l10n.tripStartSetStartingPoint,
              fieldLabel: l10n.tripStartStartingPoint,
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
          final count = trip.stops.length;
          final key = newIdempotencyKey();
          await _book(
            context,
            ref,
            notBooked: l10n.homeNotBookedMultiStop,
            booked: l10n.homeBookedMultiStop(count, trip.car.registration),
            send: (repo) => repo.submitMultiStop(trip, idempotencyKey: key),
          );
        }
      case TripType.oneWay:
        // One page for both ends: the start is pre-filled from GPS, so the
        // customer usually just types where they're going.
        final route = await Navigator.of(context).push<OneWayRoute>(
          MaterialPageRoute(builder: (_) => const OneWayRouteScreen()),
        );
        if (route == null || !context.mounted) return;
        final trip = await Navigator.of(context).push<OneWayTrip>(
          MaterialPageRoute(
            builder: (_) => OneWayDetailsScreen(
              start: route.start,
              destination: route.destination,
            ),
          ),
        );
        if (trip != null && context.mounted) {
          final key = newIdempotencyKey();
          await _book(
            context,
            ref,
            notBooked: l10n.homeNotBookedOneWay,
            booked: l10n.homeBookedOneWay(
              trip.estimatedTravelTime.inMinutes,
              trip.car.registration,
              trip.destination.address,
            ),
            send: (repo) => repo.submitOneWay(trip, idempotencyKey: key),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = user.name.split(' ').first;
    final t = SkylineTokens.of(context);
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;

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
                tooltip: l10n.homeYourProfile,
                onPressed: onOpenAccount,
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
                  Text(l10n.homeHello(firstName), style: t.body(size: 15)),
                  const SizedBox(height: Skyline.s4),
                  Text(l10n.homeWhereTo, style: text.headlineMedium),
                  const SizedBox(height: Skyline.s24),
                  Text(l10n.homeBookADriver, style: t.title(16)),
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

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final steps = <(IconData, String)>[
      (Icons.touch_app_rounded, l10n.homeHowStepPick),
      (Icons.place_rounded, l10n.homeHowStepSet),
      (Icons.directions_car_rounded, l10n.homeHowStepDrive),
    ];
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
          Text(l10n.homeHowTitle, style: t.title(16)),
          const SizedBox(height: Skyline.s4),
          Text(l10n.homeHowBody, style: t.body(size: 13)),
          const SizedBox(height: Skyline.s16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, (icon, label)) in steps.indexed) ...[
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
