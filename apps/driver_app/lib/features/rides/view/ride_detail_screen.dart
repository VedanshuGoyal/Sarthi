import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/ride.dart';
import '../rides_providers.dart';
import 'ride_format.dart';
import 'widgets/ride_widgets.dart';

/// Everything about one ride, and the one button that moves it on.
///
/// Opened from the Rides panel or Home's next-ride card for the driver's own
/// rides, and from the requests feed for an open one (then the actions are
/// Accept / Decline). The bottom bar's primary action follows the status:
/// I've arrived → Start trip → Complete trip. Before starting, the driver can
/// also hand the ride back.
class RideDetailScreen extends ConsumerWidget {
  const RideDetailScreen({super.key, required this.ride});

  /// The ride as it was when opened. For the driver's own rides the screen
  /// follows [myRidesViewModelProvider], so it updates as actions land.
  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rides = ref.watch(myRidesViewModelProvider);
    final duty = ref.watch(dutyViewModelProvider);
    final current = rides.byId(ride.id) ?? ride;
    final isRequest = current.status == RideStatus.requested;
    final busy = isRequest
        ? duty.isBusy(current.id)
        : rides.busyRideId == current.id;
    final t = SkylineTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isRequest ? 'Ride request' : 'Ride details'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Skyline.s16),
            child: Center(child: RideStatusChip(status: current.status)),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Skyline.s20,
              Skyline.s8,
              Skyline.s20,
              Skyline.s24,
            ),
            children: [
              _Summary(ride: current),
              if (current.status.isActive ||
                  current.status == RideStatus.completed) ...[
                const SizedBox(height: Skyline.s16),
                _Progress(ride: current),
              ],
              const SizedBox(height: Skyline.s16),
              _RouteCard(ride: current, showNavigate: !isRequest),
              if (current.customer != null) ...[
                const SizedBox(height: Skyline.s16),
                _CustomerCard(customer: current.customer!),
              ],
              if (current.car != null) ...[
                const SizedBox(height: Skyline.s16),
                _CarCard(car: current.car!),
              ],
              if (isRequest) ...[
                const SizedBox(height: Skyline.s16),
                Text(
                  "The customer's name and number appear once you accept.",
                  style: t.body(size: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: _ActionBar(ride: current, busy: busy),
    );
  }
}

/// When, how long, and how much.
class _Summary extends StatelessWidget {
  const _Summary({required this.ride});

  final Ride ride;

  /// The header's time note: how soon the ride starts, or — once the driver
  /// is on it — what has happened.
  static String _timing(Ride ride) => switch (ride.status) {
    RideStatus.arrived =>
      'At pickup since ${RideFormat.time(ride.arrivedAt ?? ride.scheduledAt)}',
    RideStatus.inProgress =>
      'Started ${RideFormat.time(ride.startedAt ?? ride.scheduledAt)}',
    RideStatus.completed =>
      'Done ${RideFormat.when(ride.completedAt ?? ride.endsAt)}',
    _ => RideFormat.relative(ride.scheduledAt),
  };

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(Skyline.s20),
      decoration: BoxDecoration(
        color: t.primary,
        borderRadius: BorderRadius.circular(Skyline.radiusLg),
        boxShadow: t.primaryGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(tripKindIcon(ride.kind), color: t.onPrimary, size: 20),
              const SizedBox(width: Skyline.s8),
              Text(
                ride.kind.label,
                style: t.label(size: 14, color: t.onPrimary),
              ),
              const Spacer(),
              Text(
                _timing(ride),
                style: t.label(
                  size: 13,
                  color: t.onPrimary.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: Skyline.s16),
          Text(
            RideFormat.when(ride.scheduledAt),
            style: t.heading(24, color: t.onPrimary),
          ),
          const SizedBox(height: Skyline.s4),
          Text(
            '${RideFormat.span(ride)} · until ~${RideFormat.time(ride.endsAt)}',
            style: t.body(size: 14, color: t.onPrimary.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: Skyline.s20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                RideFormat.rupees(ride.fareRupees),
                style: t.figure(30, color: t.onPrimary),
              ),
              const SizedBox(width: Skyline.s8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  ride.fareEstimated ? 'estimated fare' : 'trip fare',
                  style: t.body(
                    size: 13,
                    color: t.onPrimary.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Accepted → At pickup → On trip → Completed, with the time each happened.
class _Progress extends StatelessWidget {
  const _Progress({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final steps = <(String, DateTime?)>[
      ('Accepted', ride.acceptedAt),
      ('At pickup', ride.arrivedAt),
      ('On trip', ride.startedAt),
      ('Done', ride.completedAt),
    ];
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Row(
        children: [
          for (final (i, (label, at)) in steps.indexed) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 30),
                  color: at != null ? t.signal : t.hairline,
                ),
              ),
            Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: at != null ? t.signal : t.sunken,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    at != null ? Icons.check_rounded : Icons.circle,
                    size: at != null ? 16 : 6,
                    color: at != null ? t.onPrimary : t.outline,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: t.label(size: 11.5, color: at != null ? t.ink : null),
                ),
                Text(
                  at != null ? RideFormat.time(at) : ' ',
                  style: t.body(size: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.ride, required this.showNavigate});

  final Ride ride;
  final bool showNavigate;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    // Head for the pickup until the trip starts, then for where it ends.
    final target = ride.status == RideStatus.inProgress
        ? ride.finalPlace
        : ride.pickup;
    final distance = ride.distanceM;
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Route',
            trailing: distance != null
                ? RideFact(
                    icon: Icons.near_me_rounded,
                    text: '${RideFormat.distance(distance)} away',
                  )
                : null,
          ),
          RouteTimeline(ride: ride),
          if (showNavigate && ride.status != RideStatus.completed) ...[
            const SizedBox(height: Skyline.s16),
            OutlinedButton.icon(
              onPressed: () => _navigate(context, target),
              icon: const Icon(Icons.navigation_rounded),
              label: Text(
                ride.status == RideStatus.inProgress
                    ? 'Navigate to drop'
                    : 'Navigate to pickup',
              ),
            ),
          ],
          if (ride.kind == TripKind.multiStop && ride.car == null) ...[
            const SizedBox(height: Skyline.s12),
            Text(
              "The customer will hand over their car at the pickup.",
              style: t.body(size: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> _navigate(BuildContext context, RidePlace place) async {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${place.lat},${place.lng}',
      'travelmode': 'driving',
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open Maps on this phone.")),
      );
    }
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer});

  final RideCustomer customer;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final initial = customer.name.isEmpty ? '?' : customer.name[0];
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: t.primarySoft,
            child: Text(
              initial.toUpperCase(),
              style: t.title(17, color: t.primaryText),
            ),
          ),
          const SizedBox(width: Skyline.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customer.name, style: t.title(15)),
                Text(
                  RideFormat.phone(customer.phoneE164),
                  style: t.body(size: 13),
                ),
              ],
            ),
          ),
          IconButton.filled(
            tooltip: 'Call customer',
            style: IconButton.styleFrom(
              backgroundColor: t.primarySoft,
              foregroundColor: t.primaryText,
            ),
            onPressed: () async {
              final ok = await launchUrl(
                Uri(scheme: 'tel', path: customer.phoneE164),
              );
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Couldn't start a call.")),
                );
              }
            },
            icon: const Icon(Icons.call_rounded),
          ),
        ],
      ),
    );
  }
}

class _CarCard extends StatelessWidget {
  const _CarCard({required this.car});

  final RideCar car;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.sunken,
              borderRadius: BorderRadius.circular(Skyline.radiusSm),
            ),
            child: Icon(Icons.directions_car_filled_rounded, color: t.inkMuted),
          ),
          const SizedBox(width: Skyline.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Customer's car", style: t.body(size: 12.5)),
                Text(
                  [
                    car.carTypeLabel,
                    if (car.transmissionLabel.isNotEmpty) car.transmissionLabel,
                  ].join(' · '),
                  style: t.title(15),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: t.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              car.registration,
              style: t.figure(14, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom bar: the step that moves the ride on, plus "hand back".
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.ride, required this.busy});

  final Ride ride;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SkylineTokens.of(context);
    final (label, action) = switch (ride.status) {
      RideStatus.requested => ('Accept ride', RideAction.accept),
      RideStatus.accepted => ("I've arrived at pickup", RideAction.arrive),
      RideStatus.arrived => ('Start trip', RideAction.start),
      RideStatus.inProgress => ('Complete trip', RideAction.complete),
      _ => (null, null),
    };
    if (label == null || action == null) return const SizedBox.shrink();

    final secondary = switch (ride.status) {
      RideStatus.requested => ('Decline', RideAction.decline),
      RideStatus.accepted ||
      RideStatus.arrived => ("Can't make it", RideAction.release),
      _ => null,
    };

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        boxShadow: t.floatShadow,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Skyline.radiusLg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Skyline.s20,
                Skyline.s16,
                Skyline.s20,
                Skyline.s16,
              ),
              child: Row(
                children: [
                  if (secondary != null) ...[
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => _run(context, ref, secondary.$2),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(
                            Skyline.controlHeight,
                          ),
                        ),
                        child: Text(secondary.$1),
                      ),
                    ),
                    const SizedBox(width: Skyline.s12),
                  ],
                  Expanded(
                    flex: 3,
                    child: FilledButton(
                      onPressed: busy ? null : () => _run(context, ref, action),
                      child: busy
                          ? SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: t.inkFaint,
                              ),
                            )
                          : Text(label, textAlign: TextAlign.center),
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

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    RideAction action,
  ) async {
    // Starting asks for the customer's code instead of a yes/no.
    String? otp;
    if (action == RideAction.start) {
      otp = await showDialog<String>(
        context: context,
        builder: (_) => const _StartCodeDialog(),
      );
      if (otp == null || !context.mounted) return;
    } else {
      final confirm = await _confirm(context, action);
      if (!confirm || !context.mounted) return;
    }

    final String? error;
    switch (action) {
      case RideAction.accept:
        error = await ref.read(dutyViewModelProvider).accept(ride);
      case RideAction.decline:
        error = await ref.read(dutyViewModelProvider).decline(ride);
      default:
        error = await ref
            .read(myRidesViewModelProvider)
            .act(ride, action, otp: otp);
    }
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      // A request someone else took has left the feed; nothing to act on.
      final gone =
          action == RideAction.accept &&
          !ref.read(dutyViewModelProvider).requests.any((r) => r.id == ride.id);
      if (gone) Navigator.of(context).pop();
      return;
    }
    final done = switch (action) {
      RideAction.accept => 'Ride accepted — it\'s in your upcoming rides.',
      RideAction.decline => 'Request hidden.',
      RideAction.release => 'Ride handed back.',
      RideAction.start => 'Trip started. Drive safe!',
      RideAction.complete =>
        'Trip complete — ${RideFormat.rupees(ride.fareRupees)} added to earnings.',
      _ => null,
    };
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    if (action == RideAction.decline || action == RideAction.release) {
      Navigator.of(context).pop();
    }
  }

  /// Steps that are hard to undo ask first.
  Future<bool> _confirm(BuildContext context, RideAction action) async {
    final (title, body, yes) = switch (action) {
      RideAction.complete => (
        'Complete the trip?',
        'Confirm the trip is over and the car is back with the customer.',
        'Complete',
      ),
      RideAction.release => (
        'Hand this ride back?',
        'It goes back to other drivers nearby, and leaves your list.',
        'Hand back',
      ),
      _ => (null, null, null),
    };
    if (title == null) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(yes!),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Asks for the 4-digit code shown in the customer's app — the proof that the
/// driver is with the right customer before the trip can start. Pops with
/// the code, or null if cancelled.
class _StartCodeDialog extends StatefulWidget {
  const _StartCodeDialog();

  @override
  State<_StartCodeDialog> createState() => _StartCodeDialogState();
}

class _StartCodeDialogState extends State<_StartCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _complete => _controller.text.length == 4;

  void _submit() {
    if (_complete) Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return AlertDialog(
      title: const Text('Enter start code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ask the customer for the 4-digit code shown in their MOJUD app.',
            style: t.body(size: 15),
          ),
          const SizedBox(height: Skyline.s16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 4,
            textAlign: TextAlign.center,
            style: t.figure(28).copyWith(letterSpacing: 12),
            decoration: const InputDecoration(
              hintText: '• • • •',
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _complete ? _submit : null,
          child: const Text('Start trip'),
        ),
      ],
    );
  }
}
