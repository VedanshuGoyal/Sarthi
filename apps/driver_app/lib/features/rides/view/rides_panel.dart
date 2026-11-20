import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../domain/ride.dart';
import '../rides_providers.dart';
import '../view_model/my_rides_view_model.dart';
import 'ride_detail_screen.dart';
import 'widgets/ride_widgets.dart';

/// The Rides tab: the driver's own rides in four lists — Upcoming (accepted,
/// not yet reached), Ongoing (at the pickup or driving), Completed, and
/// Cancelled (the customer called it off after the driver took it).
class RidesPanel extends ConsumerWidget {
  const RidesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(myRidesViewModelProvider);
    final l10n = context.l10n;
    final tabs = <(String, List<Ride>, PanelMessage)>[
      (
        l10n.ridesPanelTabUpcoming,
        vm.upcoming,
        PanelMessage(
          icon: Icons.event_available_rounded,
          title: l10n.ridesPanelEmptyUpcomingTitle,
          body: l10n.ridesPanelEmptyUpcomingBody,
        ),
      ),
      (
        l10n.ridesPanelTabOngoing,
        vm.ongoing,
        PanelMessage(
          icon: Icons.local_taxi_rounded,
          title: l10n.ridesPanelEmptyOngoingTitle,
          body: l10n.ridesPanelEmptyOngoingBody,
        ),
      ),
      (
        l10n.ridesPanelTabCompleted,
        vm.completed,
        PanelMessage(
          icon: Icons.task_alt_rounded,
          title: l10n.ridesPanelEmptyCompletedTitle,
          body: l10n.ridesPanelEmptyCompletedBody,
        ),
      ),
      (
        l10n.ridesPanelTabCancelled,
        vm.cancelled,
        PanelMessage(
          icon: Icons.event_busy_rounded,
          title: l10n.ridesPanelEmptyCancelledTitle,
          body: l10n.ridesPanelEmptyCancelledBody,
        ),
      ),
    ];

    return DefaultTabController(
      length: tabs.length,
      // Open on Ongoing when a ride is underway — that's what the driver
      // needs.
      initialIndex: vm.ongoing.isNotEmpty ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.ridesPanelTitle),
          bottom: TabBar(
            tabs: [
              for (final (label, rides, _) in tabs)
                Tab(text: rides.isEmpty ? label : '$label · ${rides.length}'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final (_, rides, empty) in tabs)
              _RideList(vm: vm, rides: rides, empty: empty),
          ],
        ),
      ),
    );
  }
}

class _RideList extends StatelessWidget {
  const _RideList({required this.vm, required this.rides, required this.empty});

  final MyRidesViewModel vm;
  final List<Ride> rides;
  final PanelMessage empty;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (!vm.hasLoaded) {
      content = const Padding(
        padding: EdgeInsets.only(top: Skyline.s32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (rides.isEmpty && vm.error != null) {
      content = PanelMessage(
        icon: Icons.cloud_off_rounded,
        title: context.l10n.ridesPanelLoadFailed,
        body: vm.error!,
        action: OutlinedButton(
          onPressed: vm.load,
          child: Text(context.l10n.commonTryAgain),
        ),
      );
    } else if (rides.isEmpty) {
      content = empty;
    } else {
      content = Column(
        children: [
          for (final ride in rides) ...[
            RideCard(
              ride: ride,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RideDetailScreen(ride: ride)),
              ),
            ),
            const SizedBox(height: Skyline.s12),
          ],
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: vm.load,
      child: ListView(
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
