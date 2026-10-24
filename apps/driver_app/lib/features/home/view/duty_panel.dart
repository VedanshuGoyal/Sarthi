import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../auth/domain/driver.dart';
import '../../rides/domain/ride.dart';
import '../../rides/rides_providers.dart';
import '../../rides/view/ride_detail_screen.dart';
import '../../rides/view/ride_format.dart';
import '../../rides/view/widgets/ride_widgets.dart';

/// The Home tab: the on-duty switch, the ride that needs the driver next,
/// today's numbers, and — while online — the open ride requests nearby.
class DutyPanel extends ConsumerWidget {
  const DutyPanel({super.key, required this.driver});

  final Driver driver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duty = ref.watch(dutyViewModelProvider);
    final rides = ref.watch(myRidesViewModelProvider);
    final earnings = ref.watch(earningsViewModelProvider).earnings;
    final t = SkylineTokens.of(context);
    final current = rides.current;
    final firstName = driver.name.split(' ').first;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: Skyline.s20,
        title: const Text('Sarthi Driver'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Skyline.s20),
            child: _DutyDot(online: duty.isOnline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            duty.refresh(locate: true),
            rides.load(),
            ref.read(earningsViewModelProvider).load(),
          ]);
        },
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
                    Text('Hello, $firstName', style: t.body(size: 15)),
                    const SizedBox(height: Skyline.s4),
                    Text(
                      duty.isOnline ? "You're on duty" : 'Ready to drive?',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: Skyline.s20),
                    _DutyCard(
                      online: duty.isOnline,
                      switching: duty.isSwitching,
                      onChanged: (online) => duty.setOnline(online),
                    ),
                    if (duty.error != null && !duty.isOnline) ...[
                      const SizedBox(height: Skyline.s12),
                      Text(
                        duty.error!,
                        style: t.body(size: 13, color: t.danger),
                      ),
                    ],
                    const SizedBox(height: Skyline.s16),
                    _TodayStrip(
                      rupees: earnings.today.rupees,
                      rides: earnings.today.rides,
                      upcoming: rides.upcoming.length + rides.ongoing.length,
                    ),
                    if (current != null) ...[
                      const SizedBox(height: Skyline.s24),
                      SectionHeader(
                        title: current.status == RideStatus.accepted
                            ? 'Your next ride'
                            : 'Ride in progress',
                      ),
                      RideCard(
                        ride: current,
                        onTap: () => _open(context, current),
                      ),
                    ],
                    const SizedBox(height: Skyline.s24),
                    SectionHeader(
                      title: 'Ride requests',
                      trailing: duty.isOnline
                          ? (duty.isLoading
                                ? SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: t.signal,
                                    ),
                                  )
                                : Text(
                                    '${duty.requests.length} open',
                                    style: t.label(),
                                  ))
                          : null,
                    ),
                    ..._requests(context, ref),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _requests(BuildContext context, WidgetRef ref) {
    final duty = ref.watch(dutyViewModelProvider);
    if (!duty.isOnline) {
      return const [
        PanelMessage(
          icon: Icons.power_settings_new_rounded,
          title: "You're offline",
          body: 'Go on duty to see rides booked near you.',
        ),
      ];
    }
    if (duty.requests.isEmpty) {
      return [
        PanelMessage(
          icon: duty.error != null
              ? Icons.cloud_off_rounded
              : Icons.radar_rounded,
          title: duty.error != null
              ? "Couldn't load requests"
              : 'No requests right now',
          body:
              duty.error ??
              'New bookings near you show up here. We check every 20 '
                  "seconds while you're on duty.",
          action: duty.error != null
              ? OutlinedButton(
                  onPressed: () => duty.refresh(locate: true),
                  child: const Text('Try again'),
                )
              : null,
        ),
      ];
    }
    return [
      if (!duty.hasPosition)
        Padding(
          padding: const EdgeInsets.only(bottom: Skyline.s12),
          child: Text(
            "Turn on location to see how far each pickup is. Showing all "
            "open rides.",
            style: SkylineTokens.of(context).body(size: 13),
          ),
        ),
      for (final ride in duty.requests) ...[
        RideCard(
          ride: ride,
          showStatus: false,
          onTap: () => _open(context, ride),
          footer: _RequestActions(
            busy: duty.isBusy(ride.id),
            onDecline: () => _decline(context, ref, ride),
            onAccept: () => _accept(context, ref, ride),
          ),
        ),
        const SizedBox(height: Skyline.s12),
      ],
    ];
  }

  void _open(BuildContext context, Ride ride) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RideDetailScreen(ride: ride)));
  }

  Future<void> _accept(BuildContext context, WidgetRef ref, Ride ride) async {
    final error = await ref.read(dutyViewModelProvider).accept(ride);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            error ?? 'Ride accepted for ${RideFormat.when(ride.scheduledAt)}.',
          ),
        ),
      );
  }

  Future<void> _decline(BuildContext context, WidgetRef ref, Ride ride) async {
    final error = await ref.read(dutyViewModelProvider).decline(ride);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// A small "Online" / "Offline" pill for the app bar.
class _DutyDot extends StatelessWidget {
  const _DutyDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: online ? t.success : t.outline,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          online ? 'Online' : 'Offline',
          style: t.label(size: 13, color: online ? t.success : t.inkMuted),
        ),
      ],
    );
  }
}

/// The navy hero card with the big on/off duty switch.
class _DutyCard extends StatelessWidget {
  const _DutyCard({
    required this.online,
    required this.switching,
    required this.onChanged,
  });

  final bool online;
  final bool switching;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Semantics(
      toggled: online,
      label: 'On duty',
      // The fill lives on the decoration with its shadow (a shadow over a
      // separately-filled Material would tint the card grey); the Material
      // on top is transparent and only carries the ink ripple.
      child: AnimatedContainer(
        duration: Skyline.motion,
        curve: Skyline.easing,
        decoration: BoxDecoration(
          color: online ? t.primary : t.surface,
          borderRadius: BorderRadius.circular(Skyline.radiusLg),
          boxShadow: online ? t.primaryGlow : t.cardShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Skyline.radiusLg),
            onTap: switching ? null : () => onChanged(!online),
            child: Padding(
              padding: const EdgeInsets.all(Skyline.s20),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: online ? t.signal : t.primarySoft,
                      borderRadius: BorderRadius.circular(Skyline.radius),
                    ),
                    child: switching
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: online ? t.onPrimary : t.primaryText,
                            ),
                          )
                        : Icon(
                            online
                                ? Icons.local_taxi_rounded
                                : Icons.power_settings_new_rounded,
                            color: online ? t.onPrimary : t.primaryText,
                            size: 26,
                          ),
                  ),
                  const SizedBox(width: Skyline.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          online ? 'On duty' : 'Off duty',
                          style: t.title(
                            18,
                            weight: FontWeight.w800,
                            color: online ? t.onPrimary : t.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          online
                              ? 'Getting ride requests near you'
                              : 'Tap to start getting ride requests',
                          style: t.body(
                            size: 13,
                            color: online
                                ? t.onPrimary.withValues(alpha: 0.78)
                                : t.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: online,
                    onChanged: switching ? null : onChanged,
                    thumbColor: WidgetStateProperty.all(Colors.white),
                    trackColor: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.selected)
                          ? t.signal
                          : t.outline,
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

/// Today's earnings and rides, and how many rides the driver holds.
class _TodayStrip extends StatelessWidget {
  const _TodayStrip({
    required this.rupees,
    required this.rides,
    required this.upcoming,
  });

  final int rupees;
  final int rides;
  final int upcoming;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Today', RideFormat.rupees(rupees)),
      ('Trips today', '$rides'),
      ('Booked', '$upcoming'),
    ];
    final t = SkylineTokens.of(context);
    return SkylineCard(
      padding: const EdgeInsets.symmetric(
        vertical: Skyline.s16,
        horizontal: Skyline.s8,
      ),
      child: Row(
        children: [
          for (final (i, (label, value)) in items.indexed) ...[
            if (i > 0) Container(width: 1, height: 36, color: t.hairline),
            Expanded(
              child: Column(
                children: [
                  Text(value, style: t.figure(20)),
                  const SizedBox(height: 4),
                  Text(label, style: t.label(size: 12)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Decline / Accept under a request card.
class _RequestActions extends StatelessWidget {
  const _RequestActions({
    required this.busy,
    required this.onDecline,
    required this.onAccept,
  });

  final bool busy;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : onDecline,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: Skyline.s12),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: busy ? null : onAccept,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: busy
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: t.inkFaint,
                    ),
                  )
                : const Text('Accept ride'),
          ),
        ),
      ],
    );
  }
}
