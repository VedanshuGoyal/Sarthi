import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/my_booking.dart';
import '../ride_providers.dart';
import '../view_model/my_bookings_view_model.dart';
import 'rate_ride_sheet.dart';
import 'ride_details_screen.dart';
import 'widgets/my_ride_card.dart';

/// The Activity tab: the customer's bookings in two lists — Upcoming (not
/// finished yet, soonest first, with driver and start code) and Completed
/// (finished or cancelled, latest first, with who drove and the fare).
///
/// The signed-in shell keeps the list fresh; each list also pulls to refresh.
/// Tapping a ride opens its details; an unrated completed ride's "Rate your
/// trip" opens the rating sheet.
class ActivityPanel extends ConsumerWidget {
  const ActivityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(myBookingsViewModelProvider);
    final tabs = <(String, List<MyBooking>, _EmptyMessage)>[
      (
        'Upcoming',
        vm.active,
        const _EmptyMessage(
          icon: Icons.event_available_rounded,
          title: 'No upcoming rides',
          body: 'Rides you book from Home show up here until they finish.',
        ),
      ),
      (
        'Completed',
        vm.past,
        const _EmptyMessage(
          icon: Icons.task_alt_rounded,
          title: 'No completed rides yet',
          body: 'Finished trips and their fares show up here.',
        ),
      ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Activity'),
          bottom: TabBar(
            tabs: [
              for (final (label, bookings, _) in tabs)
                Tab(
                  text: bookings.isEmpty
                      ? label
                      : '$label · ${bookings.length}',
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final (_, bookings, empty) in tabs)
              _BookingList(vm: vm, bookings: bookings, empty: empty),
          ],
        ),
      ),
    );
  }
}

/// Opens the details screen of the ride with [bookingId].
Future<void> openRideDetails(BuildContext context, String bookingId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RideDetailsScreen(bookingId: bookingId),
      ),
    );

class _BookingList extends StatelessWidget {
  const _BookingList({
    required this.vm,
    required this.bookings,
    required this.empty,
  });

  final MyBookingsViewModel vm;
  final List<MyBooking> bookings;
  final _EmptyMessage empty;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (!vm.hasLoaded) {
      content = const Padding(
        padding: EdgeInsets.only(top: Skyline.s32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (bookings.isEmpty && vm.error != null) {
      content = _EmptyMessage(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load your rides",
        body: vm.error!,
        action: OutlinedButton(
          onPressed: vm.load,
          child: const Text('Try again'),
        ),
      );
    } else if (bookings.isEmpty) {
      content = empty;
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final booking in bookings) ...[
            MyRideCard(
              booking: booking,
              driverPhoto: vm.driverPhoto(booking),
              onTap: () => openRideDetails(context, booking.id),
              onRate: () => showRateRideSheet(context, booking),
            ),
            const SizedBox(height: Skyline.s12),
          ],
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: vm.load,
      child: ListView(
        // Pull-to-refresh works even when the list is short or empty.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Skyline.s20,
          Skyline.s16,
          Skyline.s20,
          Skyline.s32,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}

/// A centred icon, title and line of help for an empty or failed list.
class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Skyline.s24,
        vertical: Skyline.s32,
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: BorderRadius.circular(Skyline.radius),
            ),
            child: Icon(icon, size: 30, color: t.primaryText),
          ),
          const SizedBox(height: Skyline.s16),
          Text(title, style: t.title(17), textAlign: TextAlign.center),
          const SizedBox(height: Skyline.s4),
          Text(body, style: t.body(), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: Skyline.s16), action!],
        ],
      ),
    );
  }
}
