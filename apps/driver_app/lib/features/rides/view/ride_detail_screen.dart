import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/l10n.dart';
import '../domain/ride.dart';
import '../rides_providers.dart';
import 'ride_format.dart';
import 'ride_labels.dart';
import 'widgets/help_safety_row.dart';
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
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isRequest ? l10n.rideDetailTitleRequest : l10n.rideDetailTitle,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Skyline.s16),
            child: Center(
              child: RideStatusChip(
                status: current.status,
                label: current.statusLabelIn(l10n),
              ),
            ),
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
              if (current.status == RideStatus.cancelled) ...[
                const SizedBox(height: Skyline.s16),
                _CancelledNotice(ride: current),
              ] else if (current.status.isActive ||
                  current.status == RideStatus.completed) ...[
                const SizedBox(height: Skyline.s16),
                _Progress(ride: current),
                if (current.endedEarly || current.ranOverTime) ...[
                  const SizedBox(height: Skyline.s12),
                  _FareChangedNotice(ride: current),
                ],
                if (current.status == RideStatus.inProgress)
                  _PastBookedTimeNote(ride: current),
              ],
              if (current.status == RideStatus.arrived &&
                  current.noShowAt != null) ...[
                const SizedBox(height: Skyline.s12),
                _NoShowCard(ride: current, busy: busy),
              ],
              if (current.isTrackableAt(DateTime.now()) &&
                  ref.watch(
                    locationShareViewModelProvider.select((vm) => vm.isSharing),
                  )) ...[
                const SizedBox(height: Skyline.s12),
                const _LocationSharingNote(),
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
              if (current.status == RideStatus.completed) ...[
                const SizedBox(height: Skyline.s16),
                current.myRating == null
                    ? _RateCustomerCard(ride: current)
                    : _MyRatingCard(rating: current.myRating!),
              ],
              RideHelpSafety(ride: current),
              if (isRequest) ...[
                const SizedBox(height: Skyline.s16),
                Text(
                  current.approximate
                      ? l10n.rideDetailApproxNote
                      : l10n.rideDetailCustomerAfterAccept,
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
  static String _timing(AppLocalizations l10n, Ride ride) =>
      switch (ride.status) {
        RideStatus.arrived => l10n.rideDetailAtPickupSince(
          RideFormat.time(ride.arrivedAt ?? ride.scheduledAt),
        ),
        RideStatus.inProgress => l10n.rideDetailStartedAt(
          RideFormat.time(ride.startedAt ?? ride.scheduledAt),
        ),
        RideStatus.completed => l10n.rideDetailDoneAt(
          RideFormat.when(ride.completedAt ?? ride.endsAt),
        ),
        _ => RideFormat.relative(ride.scheduledAt),
      };

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
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
                ride.kind.labelIn(l10n),
                style: t.label(size: 14, color: t.onPrimary),
              ),
              const SizedBox(width: Skyline.s8),
              Expanded(
                child: Text(
                  _timing(l10n, ride),
                  textAlign: TextAlign.end,
                  style: t.label(
                    size: 13,
                    color: t.onPrimary.withValues(alpha: 0.75),
                  ),
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
            l10n.rideDetailSpanUntil(
              RideFormat.span(ride),
              RideFormat.time(ride.endsAt),
            ),
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
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    [
                      ride.fareEstimated
                          ? l10n.rideDetailFareEstimated
                          : l10n.rideDetailFareTrip,
                      // On a cancelled ride the payment is the fee's, shown
                      // with the cancellation.
                      if (ride.status == RideStatus.completed &&
                          ride.paymentStatus != RidePaymentStatus.none)
                        ride.paymentStatus.labelIn(l10n).toLowerCase(),
                    ].join(' · '),
                    style: t.body(
                      size: 13,
                      color: t.onPrimary.withValues(alpha: 0.75),
                    ),
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
    final l10n = context.l10n;
    final steps = <(String, DateTime?)>[
      (l10n.rideDetailStepAccepted, ride.acceptedAt),
      (l10n.rideStatusArrived, ride.arrivedAt),
      (l10n.rideStatusInProgress, ride.startedAt),
      (l10n.rideDetailStepDone, ride.completedAt),
    ];
    // Each step gets an equal share of the width, so a long label wraps
    // under its own dot instead of pushing the row past the card. The line
    // into a step is coloured once that step has happened.
    Widget line(bool visible, DateTime? reached) => Expanded(
      child: Container(
        height: 2,
        color: !visible
            ? Colors.transparent
            : (reached != null ? t.signal : t.hairline),
      ),
    );
    return SkylineCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Skyline.s4,
        vertical: Skyline.s16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, (label, at)) in steps.indexed)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      line(i > 0, at),
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
                      line(
                        i < steps.length - 1,
                        i < steps.length - 1 ? steps[i + 1].$2 : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: t.label(
                      size: 11.5,
                      color: at != null ? t.ink : null,
                    ),
                  ),
                  Text(
                    at != null ? RideFormat.time(at) : ' ',
                    textAlign: TextAlign.center,
                    style: t.body(size: 11),
                  ),
                ],
              ),
            ),
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
    final l10n = context.l10n;
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: l10n.rideDetailRoute,
            trailing: distance != null
                ? RideFact(
                    icon: Icons.near_me_rounded,
                    text: l10n.rideDetailDistanceAway(
                      RideFormat.distance(distance),
                    ),
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
                    ? l10n.rideDetailNavigateDrop
                    : l10n.rideDetailNavigatePickup,
              ),
            ),
          ],
          if (ride.kind == TripKind.multiStop && ride.car == null) ...[
            const SizedBox(height: Skyline.s12),
            Text(l10n.rideDetailCarHandover, style: t.body(size: 12.5)),
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
        SnackBar(content: Text(context.l10n.rideDetailMapsFailed)),
      );
    }
  }
}

/// The ride's cancellation, when the customer called it off: who, when and
/// why — and, when they cancelled at the pickup, the fee they owe and where
/// its payment stands. Shown in place of the step progress — there's
/// nothing left to step through.
class _CancelledNotice extends StatelessWidget {
  const _CancelledNotice({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final reason = ride.cancelReason;
    final payment = RideFormat.payment(ride);
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cancel_rounded, color: t.danger, size: 22),
          const SizedBox(width: Skyline.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.cancelLabelIn(l10n),
                  style: t.title(15, color: t.danger),
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    ride.cancelledBy == 'no_show'
                        ? reason
                        : l10n.rideDetailCancelReason(reason),
                    style: t.body(size: 13),
                  ),
                ],
                if (ride.cancelledAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    RideFormat.when(ride.cancelledAt!),
                    style: t.body(size: 12.5),
                  ),
                ],
                if (ride.hasCancellationFee) ...[
                  const SizedBox(height: Skyline.s12),
                  Text(
                    l10n.rideDetailCancellationFee(
                      RideFormat.paise(ride.cancellationFeePaise!),
                    ),
                    style: t.title(15),
                  ),
                  if (payment.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(payment, style: t.body(size: 13)),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A completed trip charged other than as booked: the customer ended it
/// before its booked time was up ([Ride.endedEarly]), or it ran past it
/// ([Ride.ranOverTime]) — what they're charged for the time used, against
/// the fare as booked.
class _FareChangedNotice extends StatelessWidget {
  const _FareChangedNotice({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final (icon, title, body) = ride.ranOverTime
        ? (
            Icons.more_time_rounded,
            l10n.rideDetailRanOverTitle,
            RideFormat.ranOver(ride),
          )
        : (
            Icons.timer_off_rounded,
            l10n.rideDetailEndedEarlyTitle,
            RideFormat.endedEarly(ride),
          );
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: t.inkMuted, size: 22),
          const SizedBox(width: Skyline.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.title(15)),
                const SizedBox(height: 2),
                Text(body, style: t.body(size: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Past the booked time — …" — shown on a trip underway once it has run
/// past its booked hours and the grace ([Ride.isPastBookedTimeAt]); nothing
/// before then. Rebuilds itself when that moment comes.
class _PastBookedTimeNote extends StatefulWidget {
  const _PastBookedTimeNote({required this.ride});

  final Ride ride;

  @override
  State<_PastBookedTimeNote> createState() => _PastBookedTimeNoteState();
}

class _PastBookedTimeNoteState extends State<_PastBookedTimeNote> {
  Timer? _passes;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_PastBookedTimeNote old) {
    super.didUpdateWidget(old);
    if (old.ride.overtimeFrom != widget.ride.overtimeFrom) _schedule();
  }

  /// Rebuilds just after the booked time and the grace are up.
  void _schedule() {
    _passes?.cancel();
    final at = widget.ride.overtimeFrom;
    if (at == null) return;
    final wait = at.difference(DateTime.now());
    if (wait >= Duration.zero) {
      _passes = Timer(wait + const Duration(seconds: 1), () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _passes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.ride.isPastBookedTimeAt(DateTime.now())) {
      return const SizedBox.shrink();
    }
    final t = SkylineTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Skyline.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.more_time_rounded, size: 16, color: t.inkMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              context.l10n.rideDetailPastBookedTime,
              style: t.body(size: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Customer not here?" — shown while the driver waits at the pickup. From
/// [Ride.noShowAt] it lets them close the ride as a no-show, so they aren't
/// left to hand it back and be counted as the one who cancelled; before
/// then it says when. Rebuilds itself when that moment comes.
class _NoShowCard extends ConsumerStatefulWidget {
  const _NoShowCard({required this.ride, required this.busy});

  final Ride ride;
  final bool busy;

  @override
  ConsumerState<_NoShowCard> createState() => _NoShowCardState();
}

class _NoShowCardState extends ConsumerState<_NoShowCard> {
  Timer? _opens;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_NoShowCard old) {
    super.didUpdateWidget(old);
    if (old.ride.noShowAt != widget.ride.noShowAt) _schedule();
  }

  /// Rebuilds once the no-show becomes possible.
  void _schedule() {
    _opens?.cancel();
    final at = widget.ride.noShowAt;
    if (at == null) return;
    final wait = at.difference(DateTime.now());
    if (wait > Duration.zero) {
      _opens = Timer(wait, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _opens?.cancel();
    super.dispose();
  }

  Future<void> _closeAsNoShow() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = context.l10n;
        return AlertDialog(
          title: Text(l10n.rideDetailNoShowDialogTitle),
          content: Text(l10n.rideDetailNoShowDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.rideDetailKeepWaiting),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.rideDetailCloseRide),
            ),
          ],
        );
      },
    );
    if (yes != true || !mounted) return;
    final error = await ref
        .read(myRidesViewModelProvider)
        .act(widget.ride, RideAction.noShow);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? context.l10n.rideDetailNoShowClosed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final open = widget.ride.canCloseAsNoShowAt(DateTime.now());
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.person_off_rounded, color: t.inkMuted, size: 22),
              const SizedBox(width: Skyline.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.rideDetailNoShowTitle, style: t.title(15)),
                    const SizedBox(height: 2),
                    Text(
                      open
                          ? l10n.rideDetailNoShowOpen
                          : l10n.rideDetailNoShowFrom(
                              RideFormat.time(widget.ride.noShowAt!),
                            ),
                      style: t.body(size: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Skyline.s12),
          OutlinedButton(
            onPressed: open && !widget.busy ? _closeAsNoShow : null,
            child: Text(l10n.rideDetailNoShowButton),
          ),
        ],
      ),
    );
  }
}

/// "Sharing your live location with the customer" — shown on the active
/// ride while [LocationShareViewModel] has a position stream open for it.
class _LocationSharingNote extends StatelessWidget {
  const _LocationSharingNote();

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Row(
      children: [
        Icon(Icons.my_location_rounded, size: 15, color: t.inkFaint),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            context.l10n.rideDetailSharingLocation,
            style: t.body(size: 12.5),
          ),
        ),
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer});

  final RideCustomer customer;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final initial = customer.name.isEmpty ? '?' : customer.name[0];
    // The backend blanks the number two hours after the ride ends.
    final hasPhone = customer.phoneE164.isNotEmpty;
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
                  hasPhone
                      ? RideFormat.phone(customer.phoneE164)
                      : l10n.rideDetailNumberHidden,
                  style: t.body(size: 13),
                ),
                Text(
                  RideFormat.customerRating(
                    customer.rating,
                    customer.ratingCount,
                  ),
                  style: t.body(size: 12.5),
                ),
              ],
            ),
          ),
          if (hasPhone)
            IconButton.filled(
              tooltip: l10n.rideDetailCallCustomer,
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
                    SnackBar(content: Text(l10n.rideDetailCallFailed)),
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
    final l10n = context.l10n;
    final transmission = car.transmissionLabelIn(l10n);
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
                Text(l10n.rideDetailCustomerCar, style: t.body(size: 12.5)),
                Text(
                  [
                    car.carTypeLabelIn(l10n),
                    if (transmission.isNotEmpty) transmission,
                  ].join(' · '),
                  style: t.title(15),
                ),
              ],
            ),
          ),
          // A request's car has no plate until the ride is accepted.
          if (car.registration.isNotEmpty)
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

/// A completed ride with no [Ride.myRating] yet: 5 tappable stars, an
/// optional note, and a Submit button that posts
/// `POST /driver/rides/{id}/rate`.
class _RateCustomerCard extends ConsumerStatefulWidget {
  const _RateCustomerCard({required this.ride});

  final Ride ride;

  @override
  ConsumerState<_RateCustomerCard> createState() => _RateCustomerCardState();
}

class _RateCustomerCardState extends ConsumerState<_RateCustomerCard> {
  final _noteController = TextEditingController();
  int _stars = 0;
  bool _busy = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0 || _busy) return;
    setState(() => _busy = true);
    final note = _noteController.text.trim();
    final error = await ref
        .read(myRidesViewModelProvider)
        .act(
          widget.ride,
          RideAction.rate,
          stars: _stars,
          note: note.isEmpty ? null : note,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.rideDetailRateTitle, style: t.title(15)),
          const SizedBox(height: Skyline.s12),
          Center(
            child: StarPicker(
              value: _stars,
              onChanged: (v) => setState(() => _stars = v),
            ),
          ),
          const SizedBox(height: Skyline.s12),
          TextField(
            controller: _noteController,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(hintText: l10n.rideDetailRateNoteHint),
          ),
          const SizedBox(height: Skyline.s8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _stars == 0 || _busy ? null : _submit,
              child: _busy
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: t.inkFaint,
                      ),
                    )
                  : Text(l10n.rideDetailRateSubmit),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the driver already gave this customer — read-only once rated.
class _MyRatingCard extends StatelessWidget {
  const _MyRatingCard({required this.rating});

  final RideRating rating;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final note = rating.note;
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Row(
        children: [
          StarRow(stars: rating.stars),
          const SizedBox(width: Skyline.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.rideDetailYouRated(rating.stars),
                  style: t.title(14),
                ),
                if (note != null && note.isNotEmpty)
                  Text(note, style: t.body(size: 12.5)),
              ],
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
    final l10n = context.l10n;
    final (label, action) = switch (ride.status) {
      RideStatus.requested => (l10n.rideDetailActionAccept, RideAction.accept),
      RideStatus.accepted => (l10n.rideDetailActionArrive, RideAction.arrive),
      RideStatus.arrived => (l10n.rideDetailActionStart, RideAction.start),
      RideStatus.inProgress => (
        l10n.rideDetailActionComplete,
        RideAction.complete,
      ),
      _ => (null, null),
    };
    if (label == null || action == null) return const SizedBox.shrink();

    final secondary = switch (ride.status) {
      RideStatus.requested => (
        l10n.rideDetailActionDecline,
        RideAction.decline,
      ),
      RideStatus.accepted ||
      RideStatus.arrived => (l10n.rideDetailActionRelease, RideAction.release),
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
                        child: Text(secondary.$1, textAlign: TextAlign.center),
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

    final rides = ref.read(myRidesViewModelProvider);
    // The customer can end the trip while the dialog is open (the
    // `ride_ended_early` push reloads the rides): it's complete already,
    // so there's nothing to send.
    final alreadyDone =
        action == RideAction.complete &&
        rides.byId(ride.id)?.status == RideStatus.completed;

    final String? error;
    switch (action) {
      case _ when alreadyDone:
        error = null;
      case RideAction.accept:
        error = await ref.read(dutyViewModelProvider).accept(ride);
      case RideAction.decline:
        error = await ref.read(dutyViewModelProvider).decline(ride);
      default:
        error = await rides.act(ride, action, otp: otp);
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
    // The latest copy: a trip the customer ended early, or one that ran past
    // its booked time, is charged for the time used, not the fare this
    // screen was built with.
    final latest = rides.byId(ride.id) ?? ride;
    final l10n = context.l10n;
    final done = switch (action) {
      RideAction.accept => l10n.rideDetailAccepted,
      RideAction.decline => l10n.rideDetailDeclined,
      RideAction.release => l10n.rideDetailReleased,
      RideAction.start => l10n.rideDetailStarted,
      RideAction.complete when latest.endedEarly =>
        l10n.rideDetailCompletedEndedEarly(
          RideFormat.rupees(latest.fareRupees),
        ),
      RideAction.complete when latest.ranOverTime =>
        l10n.rideDetailCompletedRanOver(RideFormat.ranOver(latest)),
      RideAction.complete => l10n.rideDetailCompleted(
        RideFormat.rupees(latest.fareRupees),
      ),
      _ => null,
    };
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    if (action == RideAction.decline || action == RideAction.release) {
      Navigator.of(context).pop();
    }
  }

  /// Steps that are hard to undo ask first.
  Future<bool> _confirm(BuildContext context, RideAction action) async {
    final l10n = context.l10n;
    final (title, body, yes) = switch (action) {
      RideAction.complete => (
        l10n.rideDetailConfirmCompleteTitle,
        l10n.rideDetailConfirmCompleteBody,
        l10n.rideDetailConfirmCompleteYes,
      ),
      RideAction.release => (
        l10n.rideDetailConfirmReleaseTitle,
        l10n.rideDetailConfirmReleaseBody,
        l10n.rideDetailConfirmReleaseYes,
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
            child: Text(l10n.rideDetailNotNow),
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
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.rideDetailStartCodeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.rideDetailStartCodeBody, style: t.body(size: 15)),
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
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: _complete ? _submit : null,
          child: Text(l10n.rideDetailActionStart),
        ),
      ],
    );
  }
}
