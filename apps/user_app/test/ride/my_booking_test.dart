import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/domain/trip_type.dart';
import 'package:user_app/features/ride/view_model/ride_details_view_model.dart';

import '../support/fake_booking_server.dart';

void main() {
  test('parses every field the contract added', () {
    final b = MyBooking.tryParse(
      bookingJson(
        status: 'completed',
        completedAt: '2030-10-26T07:40:00Z',
        myRating: {'stars': 4, 'note': 'Careful driver'},
      ),
    )!;

    check(b.tripType).equals(TripType.multiStop);
    check(b.pickupPoint!.latitude).equals(28.6315);
    // The 0,0 placeholder is "no fix", not a point in the ocean.
    check(b.destinationPoint).isNull();
    check(b.destinationAddress).equals('Hauz Khas Village');
    check(b.stops.length).equals(2);
    check(b.stops.first.task).equals('Collect the prescription');
    check(b.stops.first.address).equals('Apollo Pharmacy');
    check(
      b.stops.first.departBy,
    ).equals(DateTime.utc(2030, 10, 26, 6).toLocal());
    check(b.estimatedMinutes).equals(150);
    check(b.duration).equals(const Duration(minutes: 150));
    check(b.carType).equals(CarType.sedan);
    check(b.transmission).equals(Transmission.manual);
    check(b.driverRating).equals(4.7);
    check(b.driverRatingCount).equals(12);
    check(b.driverFirstName).equals('Ravi');
    check(b.acceptedAt).equals(DateTime.utc(2030, 10, 25, 5).toLocal());
    check(b.completedAt).equals(DateTime.utc(2030, 10, 26, 7, 40).toLocal());
    check(b.myRating!.stars).equals(4);
    check(b.myRating!.note).equals('Careful driver');
    check(b.canRate).isFalse();
  });

  test('a cancelled booking says who cancelled and why', () {
    final b = MyBooking.tryParse(
      bookingJson(status: 'cancelled', cancelReason: 'Plans changed'),
    )!;
    check(b.cancelledBy).equals('customer');
    check(b.cancelledAt).isNotNull();
    check(b.cancellationSummary).equals('Cancelled by you · Plans changed');
    check(b.canCancel).isFalse();
  });

  test('an old payload without the new fields still parses', () {
    final b = MyBooking.tryParse({
      'id': 'old',
      'tripType': 'roundTrip',
      'status': 'accepted',
      'scheduledAt': '2030-10-26T05:00:00Z',
      'farePaise': 44000,
      'pickup': {'address': 'Connaught Place'},
      'stopCount': 3,
      'driver': {'name': 'Ravi', 'phoneE164': '+91980'},
    })!;
    check(b.pickupPoint).isNull();
    check(b.stops).isEmpty();
    check(b.stopCount).equals(3);
    check(b.hours).isNull();
    check(b.carType).isNull();
    check(b.driverRating).isNull();
    check(b.driverRatingCount).equals(0);
    check(b.createdAt).isNull();
    check(b.myRating).isNull();
    check(b.canCancel).isTrue();
  });

  test('a driver nobody has rated yet has no average', () {
    final b = MyBooking.tryParse(bookingJson(ratingCount: 0))!;
    check(b.driverRating).isNull();
    check(b.driverRatingCount).equals(0);
  });

  test('the tracking window opens an hour before an accepted ride', () {
    final b = MyBooking.tryParse(bookingJson(status: 'accepted'))!;
    final start = b.scheduledAt;
    check(
      b.isInTrackingWindow(start.subtract(const Duration(minutes: 61))),
    ).isFalse();
    check(
      b.isInTrackingWindow(start.subtract(const Duration(minutes: 60))),
    ).isTrue();
    // At the pickup or on the trip it's always open; before a driver, never.
    final far = start.subtract(const Duration(days: 3));
    check(
      MyBooking.tryParse(
        bookingJson(status: 'arrived'),
      )!.isInTrackingWindow(far),
    ).isTrue();
    check(
      MyBooking.tryParse(
        bookingJson(status: 'in_progress'),
      )!.isInTrackingWindow(far),
    ).isTrue();
    check(
      MyBooking.tryParse(
        bookingJson(status: 'requested', withDriver: false),
      )!.isInTrackingWindow(start),
    ).isFalse();
  });

  test('the timeline ends where a cancelled ride stopped', () {
    final cancelled = MyBooking.tryParse(
      bookingJson(status: 'cancelled', cancelReason: 'Plans changed'),
    )!;
    final steps = rideTimeline(cancelled);
    check(
      steps.map((s) => s.label),
    ).deepEquals(['Booked', 'Driver assigned', 'Cancelled by you']);
    check(steps.last.state).equals(MilestoneState.ended);
    check(steps.last.detail).equals('Plans changed');

    final accepted = rideTimeline(MyBooking.tryParse(bookingJson())!);
    check(accepted.map((s) => s.state)).deepEquals([
      MilestoneState.done,
      MilestoneState.current,
      MilestoneState.upcoming,
      MilestoneState.upcoming,
      MilestoneState.upcoming,
    ]);
  });
}
