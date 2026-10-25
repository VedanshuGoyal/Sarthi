import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/my_booking.dart';
import '../domain/trip_type.dart';
import '../ride_providers.dart';
import '../view_model/ride_details_view_model.dart';
import 'widgets/booking_status_pill.dart';
import 'widgets/cancel_ride_sheet.dart';
import 'widgets/driver_row.dart';
import 'widgets/live_ride_map.dart';
import 'widgets/ride_format.dart';
import 'widgets/star_rating.dart';
import 'widgets/start_code_panel.dart';

/// One ride, opened from its Activity card: where it stands, the driver's
/// live location while they're on their way, the start code, the driver,
/// the full route and plan, a timeline of what happened when — and the
/// actions that fit: cancel before the trip starts, rate it once it's done.
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

  Future<void> _cancel(RideDetailsViewModel vm, MyBooking booking) async {
    final reason = await showCancelRideSheet(context, booking);
    if (reason == null || !mounted) return;
    final cancelled = await vm.cancel(reason: reason);
    if (!mounted) return;
    _say(
      cancelled
          ? 'Your ride is cancelled.'
          : vm.cancelError ?? "Couldn't cancel the ride.",
    );
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

    final live = <Widget>[
      _StatusHeader(booking: booking),
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
          ),
        ),
      if (booking.status == BookingStatus.completed)
        _RatingCard(vm: vm, booking: booking, onSubmit: () => _rate(vm)),
    ];
    final plan = <Widget>[
      _RouteCard(booking: booking),
      _TripInfoCard(booking: booking),
      _TimelineCard(milestones: vm.timeline),
    ];
    final actions = <Widget>[
      if (booking.canCancel) ...[
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: SkylineTokens.of(context).danger,
          ),
          onPressed: vm.isCancelling ? null : () => _cancel(vm, booking),
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
        'Trip completed',
        RideFormat.when(context, b.completedAt ?? b.scheduledAt),
      ),
      BookingStatus.cancelled => (
        'Ride cancelled',
        b.cancellationSummary ?? 'This ride was cancelled.',
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
