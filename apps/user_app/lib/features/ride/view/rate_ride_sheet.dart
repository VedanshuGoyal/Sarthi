import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/my_booking.dart';
import '../ride_providers.dart';
import 'widgets/ride_format.dart';
import 'widgets/star_rating.dart';

/// Opens the rating sheet for [booking]; resolves true once a rating is
/// saved, false or null when the customer closes it ("Not now").
Future<bool?> showRateRideSheet(BuildContext context, MyBooking booking) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RateRideSheet(booking: booking),
  );
}

/// "How was your trip with Ravi?": the rating form for one completed ride,
/// as a sheet — offered by the shell when a ride finishes, and from the
/// Activity card. The stars, note and request live in that ride's
/// [rideDetailsViewModelProvider], like on its details screen.
class RateRideSheet extends ConsumerWidget {
  const RateRideSheet({super.key, required this.booking});

  final MyBooking booking;

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final vm = ref.read(rideDetailsViewModelProvider(booking.id));
    if (await vm.submitRating() && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SkylineTokens.of(context);
    final vm = ref.watch(rideDetailsViewModelProvider(booking.id));
    final b = vm.booking ?? booking;
    final name = b.driverFirstName;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Skyline.s24,
          0,
          Skyline.s24,
          Skyline.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name == null
                  ? 'How was your trip?'
                  : 'How was your trip with $name?',
              style: t.title(20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Skyline.s4),
            Text(
              '${RideFormat.tripLabel(b.tripType)} · '
              '${RideFormat.when(context, b.completedAt ?? b.scheduledAt)}',
              style: t.body(size: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Skyline.s16),
            RatingForm(
              stars: vm.ratingStars,
              onStars: vm.setRatingStars,
              initialNote: vm.ratingNote,
              onNoteChanged: vm.setRatingNote,
              isSubmitting: vm.isSubmittingRating,
              error: vm.ratingError,
              onSubmit: vm.canSubmitRating ? () => _submit(context, ref) : null,
            ),
            const SizedBox(height: Skyline.s8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
