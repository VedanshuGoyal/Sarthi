import 'package:checks/checks.dart';
import 'package:driver_app/core/services/push_service.dart';
import 'package:driver_app/features/documents/domain/document_kind.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/view/ride_format.dart';
import 'package:driver_app/features/rides/view/ride_labels.dart';
import 'package:driver_app/features/rides/view_model/my_rides_view_model.dart';
import 'package:driver_app/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

import '../rides/fakes.dart';

/// A newer server may send values this build has never heard of. None of
/// them may throw, and none may be guessed into something that offers the
/// driver a wrong action.
void main() {
  group('ride status', () {
    test('a status this build does not know is unknown, not a request', () {
      final parsed = Ride.tryParse(rideJson(status: 'on_hold'))!;

      check(parsed.status).equals(RideStatus.unknown);
      check(parsed.rawStatus).equals('on_hold');
      check(parsed.statusLabelIn(L10n.current)).equals('On hold');
      check(parsed.status.isActive).isFalse();
      check(parsed.isTrackableAt(parsed.scheduledAt)).isFalse();
    });

    test('a missing or mistyped status is unknown too', () {
      final missing = rideJson()..remove('status');
      final mistyped = rideJson()..['status'] = 7;

      check(Ride.tryParse(missing)!.status).equals(RideStatus.unknown);
      check(Ride.tryParse(mistyped)!.status).equals(RideStatus.unknown);
      check(
        Ride.tryParse(mistyped)!.statusLabelIn(L10n.current),
      ).equals('Status unknown');
    });

    test('known statuses keep their own label', () {
      final parsed = Ride.tryParse(rideJson(status: 'in_progress'))!;

      check(parsed.status).equals(RideStatus.inProgress);
      check(parsed.statusLabelIn(L10n.current)).equals('On trip');
    });

    test('an unknown status survives a merge', () {
      final held = Ride.tryParse(
        rideJson(status: 'accepted', withCustomer: true),
      )!;
      final update = Ride.tryParse(rideJson(status: 'on_hold'))!;

      check(held.mergedWith(update).rawStatus).equals('on_hold');
    });

    test('a ride in an unknown status sits in no tab and is never current', () {
      final rides = MyRidesViewModel(repository: FakeRidesRepository());
      rides.upsert(Ride.tryParse(rideJson(id: 'x', status: 'on_hold'))!);

      check(rides.upcoming).isEmpty();
      check(rides.ongoing).isEmpty();
      check(rides.completed).isEmpty();
      check(rides.cancelled).isEmpty();
      check(rides.current).isNull();
      check(rides.byId('x')).isNotNull();
    });
  });

  group('trip type', () {
    test('a type this build does not know reads as a plain trip', () {
      final parsed = Ride.tryParse(rideJson(tripType: 'outstation'))!;

      check(parsed.kind).equals(TripKind.other);
      check(parsed.kind.labelIn(L10n.current)).equals('Trip');
      // Booked 09:00–12:00: the span, not "3 h hire" from a round trip's
      // hours.
      check(
        RideFormat.span(parsed),
      ).equals(RideFormat.duration(parsed.duration));
    });
  });

  group('payment status', () {
    test('one this build does not know claims nothing', () {
      final parsed = Ride.tryParse(
        rideJson(status: 'completed', paymentStatus: 'refunded'),
      )!;

      check(parsed.paymentStatus).equals(RidePaymentStatus.none);
      check(parsed.paymentStatus.labelIn(L10n.current)).equals('');
    });
  });

  group('KYC status', () {
    test('reads the four known statuses', () {
      check(KycStatus.fromWire('incomplete')).equals(KycStatus.incomplete);
      check(KycStatus.fromWire('submitted')).equals(KycStatus.submitted);
      check(KycStatus.fromWire('verified')).equals(KycStatus.verified);
      check(KycStatus.fromWire('rejected')).equals(KycStatus.rejected);
    });

    test('a missing one is incomplete, as from a fresh profile', () {
      check(KycStatus.fromWire(null)).equals(KycStatus.incomplete);
      check(KycStatus.fromWire('')).equals(KycStatus.incomplete);
    });

    test('an unknown one is unknown, not "redo your steps"', () {
      check(KycStatus.fromWire('suspended')).equals(KycStatus.unknown);
      check(KycStatus.fromWire(3)).equals(KycStatus.unknown);
    });

    test('the record keeps the raw status and when it was submitted', () {
      final kyc = DriverKyc.fromJson({
        'profile': {
          'kycStatus': 'suspended',
          'kycSubmittedAt': '2026-11-20T10:00:00Z',
        },
      });

      check(kyc.status).equals(KycStatus.unknown);
      check(kyc.rawStatus).equals('suspended');
      check(kyc.submittedAt).equals(DateTime.utc(2026, 11, 20, 10));
    });

    test('unknown gears, genders and document kinds read as not set', () {
      final kyc = DriverKyc.fromJson({
        'profile': {
          'kycStatus': 'incomplete',
          'gender': 'nonbinary',
          'transmission': 'electric',
          'fullName': 42,
          'dateOfBirth': false,
        },
        'documents': [
          {'kind': 'pan_card'},
          {'kind': 5},
          {'kind': 'selfie'},
        ],
      });

      check(kyc.gender).isNull();
      check(kyc.transmission).isNull();
      check(kyc.dateOfBirth).isNull();
      check(kyc.uploadedKinds).deepEquals({DocumentKind.selfie});
    });
  });

  group('push type', () {
    test('reads every driver push the backend sends', () {
      for (final type in PushType.values.where((t) => t != PushType.unknown)) {
        check(PushType.fromWire(type.wireName)).equals(type);
      }
    });

    test(
      'a type this build does not know is unknown, with the raw tag kept',
      () {
        final event = PushEvent.fromData({
          'type': 'rating_received',
          'rideId': 'r1',
        });

        check(event.kind).equals(PushType.unknown);
        check(event.type).equals('rating_received');
        check(event.rideId).equals('r1');
      },
    );

    test('mistyped fields read as absent instead of throwing', () {
      final event = PushEvent.fromData({'type': 12, 'rideId': 34});

      check(event.kind).equals(PushType.unknown);
      check(event.type).equals('');
      check(event.rideId).isNull();
    });
  });
}
