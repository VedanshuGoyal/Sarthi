import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../domain/my_booking.dart';
import '../domain/trip_type.dart';
import '../ride_labels.dart';
import '../ride_providers.dart';
import '../view_model/ride_details_view_model.dart';
import 'widgets/booking_status_pill.dart';
import 'widgets/cancel_ride_sheet.dart';
import 'widgets/driver_row.dart';
import 'widgets/end_trip_dialog.dart';
import 'widgets/help_safety_row.dart';
import 'widgets/live_ride_map.dart';
import 'widgets/receipt_card.dart';
import 'widgets/ride_format.dart';
import 'widgets/ride_note.dart';
import 'widgets/star_rating.dart';
import 'widgets/start_code_panel.dart';

/// One ride, opened from its Activity card: where it stands, the driver's
/// live location while they're on their way, the start code, the driver,
/// the full route and plan, a timeline of what happened when — and the
/// actions that fit: cancel before the trip starts (free until the driver
/// reaches the pickup), end it early while it's on, pay for it — or for its
/// cancellation fee — by UPI, and rate it once it's done. Calm notes say
/// when a trip is past its booked time, and when money owed on earlier rides
/// will be added to this one's payment.
///
/// State lives in [rideDetailsViewModelProvider] for [bookingId]; this view
/// renders it and tells the view model when it's visible, so the driver's
/// location is only polled while the customer is looking. Phones get one
/// column; wide screens put the live part beside the plan.
class RideDetailsScreen extends ConsumerStatefulWidget {
  const RideDetailsScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends ConsumerState<RideDetailsScreen> {
  static const double _wideBreakpoint = 840;

  late final AppLifecycleListener _lifecycle;

  RideDetailsViewModel get _vm =>
      ref.read(rideDetailsViewModelProvider(widget.bookingId));

  @override
  void initState() {
    super.initState();
    // Polling follows what the customer can see: paused with the app.
    _lifecycle = AppLifecycleListener(
      onShow: () => _vm.startTracking(),
      onHide: () => _vm.stopTracking(),
    );
    // Deferred: providers can't notify during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _vm.startTracking();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Asks to confirm with what cancelling costs, then cancels agreeing to
  /// exactly that. If the driver reached the pickup meanwhile and it now
  /// costs more, asks again with the new fee — never cancels for one the
  /// customer didn't see.
  Future<void> _cancel(RideDetailsViewModel vm) async {
    String? lastReason;
    while (true) {
      final booking = vm.booking;
      if (booking == null || !booking.canCancel) return;
      final fee = vm.cancelFeePaise;
      final reason = await showCancelRideSheet(
        context,
        booking,
        feePaise: fee,
        initialReason: lastReason,
      );
      if (reason == null || !mounted) return;
      final outcome = await vm.cancel(reason: reason, acceptFeePaise: fee);
      if (!mounted) return;
      switch (outcome) {
        case CancelOutcome.feeChanged:
          lastReason = reason;
          continue;
        case CancelOutcome.cancelled:
          final owed = vm.booking;
          _say(
            owed != null && owed.canPay
                ? 'Your ride is cancelled. Please pay the '
                      '${RideFormat.rupees(owed.chargePaise)} fee.'
                : 'Your ride is cancelled.',
          );
        case CancelOutcome.failed:
          _say(vm.cancelError ?? "Couldn't cancel the ride.");
      }
      return;
    }
  }

  Future<void> _endTrip(RideDetailsViewModel vm, MyBooking booking) async {
    if (!await showEndTripDialog(context, booking) || !mounted) return;
    final ended = await vm.endTrip();
    if (!mounted) return;
    _say(
      ended
          ? 'Your trip has ended.'
          : vm.endTripError ?? "Couldn't end the trip.",
    );
  }

  Future<void> _pay(RideDetailsViewModel vm) async {
    if (await vm.pay() && mounted) {
      _say('Payment received. Thank you!');
    }
  }

  Future<void> _rate(RideDetailsViewModel vm) async {
    if (await vm.submitRating() && mounted) {
      _say('Thanks for rating your trip.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(rideDetailsViewModelProvider(widget.bookingId));
    final booking = vm.booking;
    if (booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your ride')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(Skyline.s24),
            child: Text("This ride isn't in your list any more."),
          ),
        ),
      );
    }

    final carried = vm.carriedDues;
    final live = <Widget>[
      _StatusHeader(booking: booking),
      if (vm.isPastBookedTime)
        RideNote(
          text: RideFormat.pastBookedTime,
          icon: Icons.schedule_rounded,
        ),
      if (vm.isTracking)
        _TrackingCard(
          line: vm.trackingLine,
          map: LiveRideMap.isAvailable && booking.pickupPoint != null
              ? LiveRideMap(
                  pickup: booking.pickupPoint,
                  driver: vm.driverLocation?.point,
                  heading: vm.driverLocation?.heading,
                )
              : null,
        ),
      if (booking.startOtp case final code?) StartCodePanel(code: code),
      if (booking.driverName case final name?)
        SkylineCard(
          padding: const EdgeInsets.all(Skyline.s16),
          child: DriverRow(
            name: name,
            title: name,
            subtitle: RideFormat.driverRating(booking),
            phone: booking.status.isActive ? booking.driverPhone : null,
            photo: vm.driverPhoto,
            avatarRadius: 28,
          ),
        ),
      if ((booking.status == BookingStatus.completed ||
              booking.hasCancellationFee) &&
          booking.paymentStatus != RidePaymentStatus.none)
        _PaymentCard(
          vm: vm,
          booking: booking,
          carried: carried,
          onPay: () => _pay(vm),
        ),
      if (booking.status == BookingStatus.completed)
        _RatingCard(vm: vm, booking: booking, onSubmit: () => _rate(vm)),
      if (carried != null && booking.status.isActive)
        RideNote(text: RideFormat.carriedNote(carried)),
      RideHelpSafety(booking: booking),
    ];
    final plan = <Widget>[
      _RouteCard(booking: booking),
      _TripInfoCard(booking: booking),
      _TimelineCard(milestones: vm.timeline),
    ];
    final actions = <Widget>[
      if (vm.canEndTrip) ...[
        OutlinedButton.icon(
          onPressed: vm.isEndingTrip ? null : () => _endTrip(vm, booking),
          icon: vm.isEndingTrip
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.stop_circle_outlined),
          label: const Text('End trip now'),
        ),
      ],
      if (booking.canCancel) ...[
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: SkylineTokens.of(context).danger,
          ),
          onPressed: vm.isCancelling ? null : () => _cancel(vm),
          icon: vm.isCancelling
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.close_rounded),
          label: const Text('Cancel ride'),
        ),
      ],
    ];

    Widget column(List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: Skyline.s12),
          child,
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(RideFormat.tripLabel(booking.tripType))),
      body: RefreshIndicator(
        onRefresh: vm.refresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final Widget content;
            if (constraints.maxWidth >= _wideBreakpoint) {
              content = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: column([...live, ...actions])),
                    const SizedBox(width: Skyline.s20),
                    Expanded(child: column(plan)),
                  ],
                ),
              );
            } else {
              content = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: column([...live, ...plan, ...actions]),
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                Skyline.s20,
                Skyline.s8,
                Skyline.s20,
                Skyline.s32,
              ),
              children: [Center(child: content)],
            );
          },
        ),
      ),
    );
  }
}

/// The ride's state in words: what kind of trip, when, and what's happening.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.booking});

  final MyBooking booking;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final b = booking;
    final name = b.driverFirstName ?? 'Your driver';
    final (headline, detail) = switch (b.status) {
      BookingStatus.requested => (
        'Finding you a driver',
        "We'll let you know as soon as one accepts.",
      ),
      BookingStatus.accepted => (
        '$name is your driver',
        'Pickup ${RideFormat.when(context, b.scheduledAt)}',
      ),
      BookingStatus.arrived => (
        '$name is at your pickup',
        'Share the start code when you meet.',
      ),
      BookingStatus.inProgress => (
        'On your trip',
        b.startedAt == null
            ? '$name is driving.'
            : 'Started ${RideFormat.when(context, b.startedAt!)}',
      ),
      BookingStatus.completed => (
        b.endedEarly ? 'Trip ended early' : 'Trip completed',
        RideFormat.endedEarly(b) ??
            RideFormat.ranOver(b) ??
            RideFormat.when(context, b.completedAt ?? b.scheduledAt),
      ),
      BookingStatus.cancelled => (
        'Ride cancelled',
        b.cancellationSummaryIn(context.l10n) ?? 'This ride was cancelled.',
      ),
      BookingStatus.expired => (
        'No driver found',
        'No driver accepted in time. Please book again.',
      ),
    };
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  borderRadius: BorderRadius.circular(Skyline.radiusSm),
                ),
                child: Icon(
                  RideFormat.tripIcon(b.tripType),
                  color: t.primaryText,
                  size: 20,
                ),
              ),
              const SizedBox(width: Skyline.s12),
              Expanded(
                child: Text(
                  RideFormat.when(context, b.scheduledAt),
                  style: t.body(size: 13),
                ),
              ),
              BookingStatusPill(status: b.status),
            ],
          ),
          const SizedBox(height: Skyline.s12),
          Text(headline, style: t.heading(22)),
          const SizedBox(height: Skyline.s4),
          Text(detail, style: t.body()),
        ],
      ),
    );
  }
}

/// The live part: the map (when this build has one) and a line on how far
/// away the driver is.
class _TrackingCard extends StatelessWidget {
  const _TrackingCard({required this.line, this.map});

  final String line;
  final Widget? map;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (map != null) ...[map!, const SizedBox(height: Skyline.s12)],
          Row(
            children: [
              Icon(Icons.near_me_rounded, size: 18, color: t.signal),
              const SizedBox(width: Skyline.s8),
              Expanded(child: Text(line, style: t.title(14))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Paying for a completed trip, or for the fee of a ride cancelled at the
/// pickup: a UPI button while it's due — for that plus whatever is
/// [carried] from the customer's other bookings — and the receipt once it's
/// paid.
class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.vm,
    required this.booking,
    required this.onPay,
    this.carried,
  });

  final RideDetailsViewModel vm;
  final MyBooking booking;
  final EarlierDues? carried;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final amount = RideFormat.rupees(booking.totalDuePaise);
    if (booking.paymentStatus == RidePaymentStatus.paid) {
      return ReceiptCard(booking: booking);
    }
    final error = vm.payError;
    final fee = booking.hasCancellationFee;
    return SkylineSection(
      title: fee ? 'Pay the cancellation fee' : 'Pay for your trip',
      subtitle:
          '${fee ? 'You cancelled after your driver reached the pickup. ' : ''}'
          'Pay $amount with any UPI app: GPay, PhonePe, Paytm or your '
          "bank's.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: vm.canPay && !vm.isPaying ? onPay : null,
            icon: vm.isPaying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_2_rounded),
            label: Text(
              vm.isPaying ? 'Waiting for UPI…' : 'Pay $amount by UPI',
            ),
          ),
          if (carried case final dues?) ...[
            const SizedBox(height: Skyline.s8),
            Text(RideFormat.carriedIncluded(dues), style: t.body(size: 13)),
          ],
          if (error != null) ...[
            const SizedBox(height: Skyline.s8),
            Text(error, style: t.body(size: 13, color: t.danger)),
          ],
        ],
      ),
    );
  }
}

/// "Rate your driver" until the customer has, then the stars they gave.
class _RatingCard extends StatelessWidget {
  const _RatingCard({
    required this.vm,
    required this.booking,
    required this.onSubmit,
  });

  final RideDetailsViewModel vm;
  final MyBooking booking;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    if (booking.myRating case final rating?) {
      return SkylineCard(
        padding: const EdgeInsets.all(Skyline.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('You rated ', style: t.title(15)),
                StarRow(stars: rating.stars),
              ],
            ),
            if (rating.note case final note?) ...[
              const SizedBox(height: Skyline.s4),
              Text('“$note”', style: t.body()),
            ],
          ],
        ),
      );
    }
    return SkylineSection(
      title: 'Rate your driver',
      subtitle: booking.driverFirstName == null
          ? 'How was your trip?'
          : 'How was your trip with ${booking.driverFirstName}?',
      child: RatingForm(
        stars: vm.ratingStars,
        onStars: vm.setRatingStars,
        initialNote: vm.ratingNote,
        onNoteChanged: vm.setRatingNote,
        isSubmitting: vm.isSubmittingRating,
        error: vm.ratingError,
        onSubmit: vm.canSubmitRating ? onSubmit : null,
      ),
    );
  }
}

/// The full route: pickup, each stop with its errand, and the destination.
class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.booking});

  final MyBooking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    // (icon, stop number, label, address, errand, leave-by)
    final places = <(IconData?, int?, String, String, String?, DateTime?)>[
      (Icons.trip_origin_rounded, null, 'Pickup', b.pickupAddress, null, null),
      for (final (i, stop) in b.stops.indexed)
        (
          null,
          i + 1,
          'Stop ${i + 1}',
          stop.address,
          stop.task.isEmpty ? null : stop.task,
          stop.departBy,
        ),
      if (b.destinationAddress case final destination?)
        (Icons.place_rounded, null, 'Destination', destination, null, null),
    ];
    return SkylineSection(
      title: 'Route',
      subtitle: b.stops.isEmpty && b.stopCount > 0
          ? '${b.stopCount} ${b.stopCount == 1 ? 'stop' : 'stops'} planned'
          : null,
      child: Column(
        children: [
          for (final (i, (icon, number, label, address, task, departBy))
              in places.indexed)
            _RouteRow(
              icon: icon,
              number: number,
              label: label,
              address: address,
              task: task,
              departBy: departBy == null
                  ? null
                  : 'Leave by ${RideFormat.time(context, departBy)}',
              last: i == places.length - 1,
            ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.label,
    required this.address,
    this.icon,
    this.number,
    this.task,
    this.departBy,
    required this.last,
  });

  final String label;
  final String address;
  final IconData? icon;
  final int? number;
  final String? task;
  final String? departBy;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                if (number case final n?)
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$n',
                      style: t.label(size: 11, color: t.primaryText),
                    ),
                  )
                else
                  Icon(icon, size: 20, color: t.primaryText),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: t.hairline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Skyline.s12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : Skyline.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: t.label(size: 12, color: t.primaryText)),
                  const SizedBox(height: 2),
                  Text(address, style: t.title(14, weight: FontWeight.w600)),
                  if (task case final task?)
                    Text(task, style: t.body(size: 13)),
                  if (departBy case final departBy?)
                    Text(
                      departBy,
                      style: t.body(size: 12.5, color: t.inkFaint),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What was booked: the kind of trip, when, for how long, the car, the fare.
class _TripInfoCard extends StatelessWidget {
  const _TripInfoCard({required this.booking});

  final MyBooking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final duration = b.duration;
    final car = RideFormat.car(b);
    final rows = <(String, String)>[
      ('Trip', RideFormat.tripLabel(b.tripType)),
      ('Starts', RideFormat.when(context, b.scheduledAt)),
      if (duration != null)
        b.tripType == TripType.roundTrip && b.hours != null
            ? ('Booked for', RideFormat.duration(duration))
            : ('Est. duration', '≈ ${RideFormat.duration(duration)}'),
      if (car != null) ('Car', car),
      ('Fare', RideFormat.fare(b)),
      if (b.bookedFarePaise case final booked? when b.chargedByTime)
        ('Booked fare', RideFormat.rupees(booked)),
      if (b.hasCancellationFee)
        ('Cancellation fee', RideFormat.rupees(b.cancellationFeePaise)),
    ];
    final t = SkylineTokens.of(context);
    return SkylineSection(
      title: 'Trip details',
      child: Column(
        children: [
          for (final (i, (label, value)) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: Skyline.s8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(label, style: t.body(size: 13.5))),
                const SizedBox(width: Skyline.s12),
                Flexible(
                  flex: 2,
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: label == 'Fare' ? t.title(16) : t.title(13.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Booked → Driver assigned → Arrived → Trip started → Completed, with the
/// time of each step reached — or ending where the ride was cancelled.
class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.milestones});

  final List<RideMilestone> milestones;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return SkylineSection(
      title: 'Timeline',
      child: Column(
        children: [
          for (final (i, step) in milestones.indexed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        _TimelineDot(state: step.state),
                        if (i < milestones.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              color: step.state == MilestoneState.done
                                  ? t.signal
                                  : t.hairline,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Skyline.s12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: i < milestones.length - 1 ? Skyline.s12 : 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.label,
                            style: t.title(
                              14,
                              color: step.state == MilestoneState.upcoming
                                  ? t.inkFaint
                                  : t.ink,
                            ),
                          ),
                          if (step.detail case final detail?)
                            Text(detail, style: t.body(size: 13)),
                          if (step.at case final at?)
                            Text(
                              RideFormat.when(context, at),
                              style: t.body(size: 12.5, color: t.inkFaint),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.state});

  final MilestoneState state;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (state) {
          MilestoneState.done => t.signal,
          MilestoneState.ended => t.danger,
          _ => t.surface,
        },
        border: Border.all(
          width: 2,
          color: switch (state) {
            MilestoneState.done => t.signal,
            MilestoneState.current => t.primary,
            MilestoneState.upcoming => t.outline,
            MilestoneState.ended => t.danger,
          },
        ),
      ),
      child: switch (state) {
        MilestoneState.done => Icon(
          Icons.check_rounded,
          size: 12,
          color: t.onPrimary,
        ),
        MilestoneState.ended => Icon(
          Icons.close_rounded,
          size: 12,
          color: t.onPrimary,
        ),
        _ => null,
      },
    );
  }
}
