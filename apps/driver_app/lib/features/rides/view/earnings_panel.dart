import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/ride.dart';
import '../rides_providers.dart';
import 'ride_detail_screen.dart';
import 'ride_format.dart';
import 'widgets/ride_widgets.dart';

/// The Earnings tab: today's total up top, the week / month / all-time
/// windows, and the completed trips that make them up.
///
/// Figures are trip fares as booked; there is no commission or payout
/// ledger yet, so this is what the driver's trips were worth, not a balance.
class EarningsPanel extends ConsumerWidget {
  const EarningsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(earningsViewModelProvider);
    final rides = ref.watch(myRidesViewModelProvider);
    final e = vm.earnings;
    final t = SkylineTokens.of(context);
    final recent = rides.completed.take(20).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([vm.load(), rides.load()]),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Skyline.s20,
            Skyline.s8,
            Skyline.s20,
            Skyline.s32,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TodayHero(period: e.today, loading: !vm.hasLoaded),
                    if (vm.hasLoaded) ...[
                      const SizedBox(height: Skyline.s8),
                      Text(
                        RideFormat.driverRating(e.rating),
                        style: t.body(size: 13),
                      ),
                    ],
                    if (vm.error != null) ...[
                      const SizedBox(height: Skyline.s12),
                      Text(vm.error!, style: t.body(size: 13, color: t.danger)),
                    ],
                    const SizedBox(height: Skyline.s16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final tiles = [
                          _PeriodTile(label: 'This week', period: e.week),
                          _PeriodTile(label: 'This month', period: e.month),
                          _PeriodTile(label: 'All time', period: e.total),
                        ];
                        // Three across when there's room, else a 2 + 1 grid.
                        if (constraints.maxWidth >= 480) {
                          return Row(
                            children: [
                              for (final (i, tile) in tiles.indexed) ...[
                                if (i > 0) const SizedBox(width: Skyline.s12),
                                Expanded(child: tile),
                              ],
                            ],
                          );
                        }
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: tiles[0]),
                                const SizedBox(width: Skyline.s12),
                                Expanded(child: tiles[1]),
                              ],
                            ),
                            const SizedBox(height: Skyline.s12),
                            SizedBox(width: double.infinity, child: tiles[2]),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: Skyline.s24),
                    const SectionHeader(title: 'Completed trips'),
                    if (recent.isEmpty)
                      const PanelMessage(
                        icon: Icons.receipt_long_rounded,
                        title: 'No trips yet',
                        body:
                            'Each trip you complete is listed here with '
                            'its fare.',
                      )
                    else
                      SkylineCard(
                        padding: const EdgeInsets.symmetric(
                          vertical: Skyline.s8,
                        ),
                        child: Column(
                          children: [
                            for (final (i, ride) in recent.indexed) ...[
                              if (i > 0)
                                const Divider(
                                  indent: Skyline.s16,
                                  endIndent: Skyline.s16,
                                ),
                              _TripRow(ride: ride),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayHero extends StatelessWidget {
  const _TodayHero({required this.period, required this.loading});

  final EarningsPeriod period;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final muted = t.onPrimary.withValues(alpha: 0.75);
    return Container(
      padding: const EdgeInsets.all(Skyline.s24),
      decoration: BoxDecoration(
        color: t.primary,
        borderRadius: BorderRadius.circular(Skyline.radiusLg),
        boxShadow: t.primaryGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's earnings", style: t.label(size: 14, color: muted)),
          const SizedBox(height: Skyline.s8),
          Text(
            loading ? '—' : RideFormat.rupees(period.rupees),
            style: t.figure(40, color: t.onPrimary),
          ),
          const SizedBox(height: Skyline.s8),
          Text(
            '${period.rides} ${period.rides == 1 ? 'trip' : 'trips'} completed',
            style: t.body(size: 14, color: muted),
          ),
        ],
      ),
    );
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({required this.label, required this.period});

  final String label;
  final EarningsPeriod period;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.label(size: 12.5)),
          const SizedBox(height: Skyline.s8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(RideFormat.rupees(period.rupees), style: t.figure(22)),
          ),
          const SizedBox(height: 2),
          Text(
            '${period.rides} ${period.rides == 1 ? 'trip' : 'trips'}',
            style: t.body(size: 12.5),
          ),
        ],
      ),
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final at = ride.completedAt ?? ride.scheduledAt;
    return ListTile(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => RideDetailScreen(ride: ride))),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: t.primarySoft,
          borderRadius: BorderRadius.circular(Skyline.radiusSm),
        ),
        child: Icon(tripKindIcon(ride.kind), size: 20, color: t.primaryText),
      ),
      title: Text(
        ride.pickup.shortName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${ride.kind.label} · ${RideFormat.when(at)}'),
      trailing: Text(RideFormat.rupees(ride.fareRupees), style: t.figure(16)),
    );
  }
}
