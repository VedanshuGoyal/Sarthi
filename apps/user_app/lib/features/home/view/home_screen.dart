import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/mojud_logo.dart';
import '../../../core/theme/deep_signal/deep_signal.dart';
import '../../../core/theme/theme_mode_controller.dart';
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
import '../../ride/view/widgets/vast_quiet/vast_quiet.dart';

/// Landing screen shown after a customer finishes registering.
///
/// Greets the user, then hosts the [TripTypeSelector] so they can pick how they
/// want to travel. The body is centred and width-capped on large screens and
/// scrolls on short ones, per the responsive-layout guideline.
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
    final tokens = DeepSignalTokens.of(context);
    // The trip chooser is the entry to the ride flow. It follows the app-wide
    // Deep Signal theme so it flips light/dark with the rest of the app, with a
    // mode-appropriate ride wash layered on so TripOptionCard's selected tint
    // reads in both modes (it resolves its wash through RideSurfaces).
    final rideTheme = rideSurfaceTheme(context);
    // The painted mountain scene is a light paper composition; in dark mode we
    // drop it and let the canvas stand rather than showing a light band.
    final showBackdrop = !tokens.isDark;

    return Theme(
      data: rideTheme,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            // The mountain scene runs up behind a transparent app bar, so the
            // peaks fill the top of the screen rather than being clipped by a
            // solid bar.
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              title: const MojudLockup(markHeight: 22),
              actions: [
                const ThemeModeToggle(),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: UserAvatar(name: user.name, radius: 16),
                    tooltip: 'Your profile',
                    onPressed: () => _openProfile(context, ref),
                  ),
                ),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                // The scene occupies the top of the viewport and fades into the
                // canvas; clamp it so it stays a header band on tall screens and
                // doesn't swallow short ones. The greeting is offset to sit over
                // the lower cloud, clear of the dark peaks, where ink text reads.
                final sceneHeight = showBackdrop
                    ? (constraints.maxHeight * 0.42).clamp(220.0, 360.0)
                    : 0.0;
                final topInset = showBackdrop
                    ? sceneHeight * 0.62
                    : MediaQuery.of(context).padding.top + kToolbarHeight + 12;
                return Stack(
                  children: [
                    if (showBackdrop)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: sceneHeight,
                        child: const VastQuietBackdrop(),
                      ),
                    SafeArea(
                      top: false,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(24, topInset, 24, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Hi $firstName, how can we drive you?',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Pick a trip type to get started.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                TripTypeSelector(
                                  onSelected: (type) =>
                                      _onTripSelected(context, ref, type),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
