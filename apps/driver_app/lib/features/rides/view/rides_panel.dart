import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/ride.dart';
import '../rides_providers.dart';
import '../view_model/my_rides_view_model.dart';
import 'ride_detail_screen.dart';
import 'widgets/ride_widgets.dart';

/// The Rides tab: the driver's own rides in three lists — Upcoming (accepted,
/// not yet reached), Ongoing (at the pickup or driving), and Completed.
class RidesPanel extends ConsumerWidget {
  const RidesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(myRidesViewModelProvider);
    final tabs = <(String, List<Ride>, PanelMessage)>[
      (
        'Upcoming',
        vm.upcoming,
        const PanelMessage(
          icon: Icons.event_available_rounded,
          title: 'No upcoming rides',
          body: 'Rides you accept from the Home tab line up here.',
        ),
      ),
      (
        'Ongoing',
        vm.ongoing,
        const PanelMessage(
          icon: Icons.local_taxi_rounded,
          title: 'Nothing underway',
          body:
              "Tap \"I've arrived\" on an upcoming ride when you reach "
              'the pickup.',
        ),
      ),
      (
        'Completed',
        vm.completed,
        const PanelMessage(
          icon: Icons.task_alt_rounded,
          title: 'No completed rides yet',
          body: 'Finished trips and their fares show up here.',
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
          title: const Text('My rides'),
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
        title: "Couldn't load your rides",
        body: vm.error!,
        action: OutlinedButton(
          onPressed: vm.load,
          child: const Text('Try again'),
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
