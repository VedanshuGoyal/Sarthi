import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/domain/document_kind.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/domain/gender.dart';
import 'package:driver_app/features/documents/domain/vehicle_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  /// A backend response with everything filled in.
  Map<String, dynamic> completeKyc() => {
    'profile': {
      'fullName': 'Asha Kumari',
      'dateOfBirth': '1995-03-02T00:00:00Z',
      'gender': 'female',
      'transmission': 'both',
      'aadhaarLast4': '9012',
      'drivingLicenseNumber': 'DL0120190012345',
      'kycStatus': 'submitted',
    },
    'documents': [
      {'kind': 'selfie', 'status': 'pending'},
      {'kind': 'aadhaar', 'status': 'verified'},
      {'kind': 'driving_license', 'status': 'pending'},
    ],
    'bankAccount': {
      'accountHolderName': 'Asha Kumari',
      'accountNumberLast4': '2345',
      'ifscCode': 'HDFC0001234',
    },
  };

  DriverKycRepository repositoryReturning(
    Object body, {
    int status = 200,
    void Function(http.Request)? onRequest,
  }) {
    return DriverKycRepository(
      baseUrl: 'http://test.invalid',
      tokenGetter: () => 'test-token',
      client: MockClient((request) async {
        onRequest?.call(request);
        return http.Response(
          body is String ? body : jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  group('DriverKyc.fromJson', () {
    test('parses the profile, documents and bank account', () {
      final kyc = DriverKyc.fromJson(completeKyc());

      check(kyc.status).equals(KycStatus.submitted);
      check(kyc.fullName).equals('Asha Kumari');
      check(
        kyc.dateOfBirth,
      ).isNotNull().has((d) => d.year, 'year').equals(1995);
      check(kyc.gender).equals(Gender.female);
      check(kyc.transmission).equals(VehicleType.both);
      check(kyc.aadhaarLast4).equals('9012');
      check(kyc.drivingLicenseNumber).equals('DL0120190012345');
      check(kyc.uploadedKinds).unorderedEquals(DocumentKind.values);
      check(kyc.bankAccount)
          .isNotNull()
          .has((a) => a.accountNumberLast4, 'accountNumberLast4')
          .equals('2345');
    });

    test('defaults to an empty, incomplete KYC for a new driver', () {
      final kyc = DriverKyc.fromJson({
        'profile': {'fullName': 'Asha', 'kycStatus': 'incomplete'},
        'documents': <dynamic>[],
      });

      check(kyc.status).equals(KycStatus.incomplete);
      check(kyc.dateOfBirth).isNull();
      check(kyc.gender).isNull();
      check(kyc.aadhaarLast4).isNull();
      check(kyc.uploadedKinds).isEmpty();
      check(kyc.bankAccount).isNull();
    });

    // A newer backend must not crash an older build sitting on a driver's
    // phone, so an unrecognised kind is skipped rather than thrown on.
    test('ignores document kinds this build does not know', () {
      final kyc = DriverKyc.fromJson({
        'profile': {'kycStatus': 'incomplete'},
        'documents': [
          {'kind': 'selfie'},
          {'kind': 'vehicle_registration'},
        ],
      });

      check(kyc.uploadedKinds).unorderedEquals([DocumentKind.selfie]);
    });

    test('treats empty strings as absent', () {
      final kyc = DriverKyc.fromJson({
        'profile': {
          'aadhaarLast4': '',
          'drivingLicenseNumber': '',
          'gender': '',
          'dateOfBirth': '',
        },
        'documents': <dynamic>[],
      });

      check(kyc.aadhaarLast4).isNull();
      check(kyc.drivingLicenseNumber).isNull();
      check(kyc.gender).isNull();
      check(kyc.dateOfBirth).isNull();
    });
  });

  group('requests', () {
    test('load sends an authenticated GET', () async {
      http.Request? seen;
      final repository = repositoryReturning(
        completeKyc(),
        onRequest: (r) => seen = r,
      );

      await repository.load();

      check(seen).isNotNull();
      check(seen!.method).equals('GET');
      check(seen!.url.path).equals('/driver/kyc');
      check(seen!.headers['Authorization']).equals('Bearer test-token');
    });

    test('updateProfile PATCHes only the fields the step collected', () async {
      http.Request? seen;
      final repository = repositoryReturning(
        completeKyc(),
        onRequest: (r) => seen = r,
      );

      await repository.updateProfile(transmission: VehicleType.manual);

      check(seen!.method).equals('PATCH');
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      check(body).deepEquals({'transmission': 'manual'});
    });

    test('updateProfile sends the date of birth as a plain date', () async {
      http.Request? seen;
      final repository = repositoryReturning(
        completeKyc(),
        onRequest: (r) => seen = r,
      );

      await repository.updateProfile(
        fullName: '  Asha Kumari  ',
        dateOfBirth: DateTime(1995, 3, 2),
        gender: Gender.female,
      );

      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      check(body['dateOfBirth']).equals('1995-03-02');
      check(body['gender']).equals('female');
      check(body['fullName']).equals('Asha Kumari');
    });

    test('setBankAccount uppercases the IFSC code', () async {
      http.Request? seen;
      final repository = repositoryReturning(
        completeKyc(),
        onRequest: (r) => seen = r,
      );

      await repository.setBankAccount(
        accountHolderName: 'Asha Kumari',
        accountNumber: '123456789012',
        ifscCode: 'hdfc0001234',
      );

      check(seen!.method).equals('POST');
      check(seen!.url.path).equals('/driver/kyc/bank-account');
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      check(body['ifscCode']).equals('HDFC0001234');
    });
  });

  group('errors', () {
    test("surfaces the backend's message and code", () async {
      final repository = repositoryReturning({
        'error': 'this Aadhaar number is already registered',
        'code': 'aadhaar_taken',
      }, status: 409);

      await check(
        repository.updateProfile(aadhaarNumber: '123456789012'),
      ).throws<KycException>((failure) {
        failure.has((e) => e.code, 'code').equals('aadhaar_taken');
        failure.has((e) => e.message, 'message').contains('already registered');
      });
    });

    test('falls back to a generic message for a non-JSON error', () async {
      final repository = repositoryReturning('<html>502</html>', status: 502);

      await check(repository.load()).throws<KycException>((failure) {
        failure.has((e) => e.code, 'code').isNull();
        failure.has((e) => e.message, 'message').isNotEmpty();
      });
    });

    test('reports an unreachable server rather than throwing raw', () async {
      final repository = DriverKycRepository(
        baseUrl: 'http://test.invalid',
        client: MockClient((_) async => throw const SocketExceptionStub()),
      );

      await check(repository.load()).throws<KycException>((failure) {
        failure
            .has((e) => e.message, 'message')
            .contains("Can't reach the server");
      });
    });
  });
}

/// Stands in for a network failure without depending on `dart:io` types.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
