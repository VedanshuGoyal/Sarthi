import 'dart:async';

import 'package:checks/checks.dart';
import 'package:driver_app/core/refresh_throttle.dart';
import 'package:driver_app/features/documents/data/document_file_store.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/domain/document_kind.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/domain/gender.dart';
import 'package:driver_app/features/documents/domain/vehicle_type.dart';
import 'package:driver_app/features/documents/view_model/document_registration_view_model.dart';
import 'package:driver_app/features/rides/view_model/duty_view_model.dart';
import 'package:driver_app/features/rides/view_model/earnings_view_model.dart';
import 'package:driver_app/features/rides/view_model/my_rides_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../rides/fakes.dart';

/// Lets the queued microtasks run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late DateTime now;
  DateTime clock() => now;

  setUp(() => now = DateTime(2026, 11, 21, 9));

  group('RefreshThrottle', () {
    test('stale until the first fetch, then for the gap after each', () {
      final throttle = RefreshThrottle(now: clock);
      check(throttle.isStale).isTrue();

      throttle.mark();
      check(throttle.isStale).isFalse();

      now = now.add(RefreshThrottle.defaultGap - const Duration(seconds: 1));
      check(throttle.isStale).isFalse();

      now = now.add(const Duration(seconds: 1));
      check(throttle.isStale).isTrue();
    });
  });

  group('refreshIfStale on the ride view models', () {
    test('my rides: skipped while fresh, read once stale', () async {
      final repo = FakeRidesRepository();
      final vm = MyRidesViewModel(repository: repo, now: clock);
      await vm.load();

      await vm.refreshIfStale();
      check(repo.myRidesCalls).equals(1);

      now = now.add(const Duration(minutes: 1));
      await vm.refreshIfStale();
      check(repo.myRidesCalls).equals(2);
    });

    test('earnings: skipped while fresh, read once stale', () async {
      final repo = FakeRidesRepository();
      final vm = EarningsViewModel(repository: repo, now: clock);
      await vm.load();

      await vm.refreshIfStale();
      check(repo.earningsCalls).equals(1);

      now = now.add(const Duration(minutes: 1));
      await vm.refreshIfStale();
      check(repo.earningsCalls).equals(2);
    });

    test('duty: nothing while off duty; on duty, re-reports and reads once '
        'the poll is stale', () async {
      final repo = FakeRidesRepository();
      final vm = DutyViewModel(
        repository: repo,
        location: FakeLocationService(),
        now: clock,
      );

      now = now.add(const Duration(minutes: 1));
      await vm.refreshIfStale();
      check(repo.requestsCalls).equals(0);
      check(repo.duty).isEmpty();

      await vm.setOnline(true);
      check(repo.requestsCalls).equals(1);

      await vm.refreshIfStale();
      check(repo.requestsCalls).equals(1);

      now = now.add(const Duration(minutes: 1));
      await vm.refreshIfStale();
      check(repo.requestsCalls).equals(2);
      check(repo.duty).deepEquals([true, true]);

      await vm.setOnline(false);
    });
  });

  group('the KYC record, reloaded while the driver works', () {
    late _GatedKyc repo;
    late DocumentRegistrationViewModel vm;

    setUp(() {
      repo = _GatedKyc();
      vm = DocumentRegistrationViewModel(
        repository: repo,
        files: _NoDisk(),
        now: clock,
      );
    });

    test('a load in flight does not undo a step saved meanwhile', () async {
      final load = vm.load();
      await vm.setVehicleType(VehicleType.manual);
      check(vm.kyc.transmission).equals(VehicleType.manual);

      // The read began before the save, so its answer predates it.
      repo.loads.single.complete(const DriverKyc());
      await load;

      check(vm.kyc.transmission).equals(VehicleType.manual);
      check(vm.isLoading).isFalse();
    });

    test('only the latest of two loads is used', () async {
      final first = vm.load();
      final second = vm.load();
      repo.loads[1].complete(const DriverKyc(status: KycStatus.verified));
      await second;
      repo.loads[0].complete(const DriverKyc(status: KycStatus.incomplete));
      await first;

      check(vm.kyc.status).equals(KycStatus.verified);
      check(vm.isLoading).isFalse();
    });

    test('a reload mid-upload leaves the photo uploading', () async {
      repo.holdUploads = true;
      final capture = vm.capturePhoto(DocumentKind.selfie, '/picked.jpg');
      await settle();
      check(
        vm.data.uploadStateFor(DocumentKind.selfie),
      ).equals(DocumentUploadState.uploading);

      final load = vm.load();
      repo.loads.single.complete(const DriverKyc());
      await load;
      check(
        vm.data.uploadStateFor(DocumentKind.selfie),
      ).equals(DocumentUploadState.uploading);
      check(vm.data.capturePathFor(DocumentKind.selfie)).equals('/picked.jpg');

      repo.upload!.complete(
        const DriverKyc(uploadedKinds: {DocumentKind.selfie}),
      );
      await capture;
      check(
        vm.data.uploadStateFor(DocumentKind.selfie),
      ).equals(DocumentUploadState.uploaded);
    });

    test('a resume refresh waits while a step is saving or a photo is '
        'uploading', () async {
      repo.holdProfile = true;
      now = now.add(const Duration(minutes: 1));
      final save = vm.setPhotoAndName(
        fullName: 'Asha Kumari',
        dateOfBirth: DateTime(1995, 3, 2),
        gender: Gender.female,
      );
      await settle();
      await vm.refreshIfStale();
      check(repo.loads).isEmpty();
      repo.profile!.complete(const DriverKyc(fullName: 'Asha Kumari'));
      await save;

      repo.holdUploads = true;
      final capture = vm.capturePhoto(DocumentKind.selfie, '/picked.jpg');
      await settle();
      await vm.refreshIfStale();
      check(repo.loads).isEmpty();
      repo.upload!.complete(const DriverKyc());
      await capture;

      // Free again: the refresh goes through, and only once.
      final refresh = vm.refreshIfStale();
      await vm.refreshIfStale();
      check(repo.loads).length.equals(1);
      repo.loads.single.complete(const DriverKyc());
      await refresh;

      await vm.refreshIfStale();
      check(repo.loads).length.equals(1);
    });
  });
}

/// A KYC backend whose loads (and, when held, uploads and profile saves)
/// answer only when the test completes them.
class _GatedKyc implements DriverKycRepository {
  final List<Completer<DriverKyc>> loads = [];
  bool holdUploads = false;
  bool holdProfile = false;
  Completer<DriverKyc>? upload;
  Completer<DriverKyc>? profile;

  @override
  Future<DriverKyc> load() {
    final answer = Completer<DriverKyc>();
    loads.add(answer);
    return answer.future;
  }

  @override
  Future<DriverKyc> uploadDocument(DocumentKind kind, String path) {
    if (!holdUploads) {
      return Future.value(DriverKyc(uploadedKinds: {kind}));
    }
    return (upload = Completer<DriverKyc>()).future;
  }

  @override
  Future<DriverKyc> updateProfile({
    VehicleType? transmission,
    String? fullName,
    DateTime? dateOfBirth,
    Gender? gender,
    String? aadhaarNumber,
    String? drivingLicenseNumber,
  }) {
    if (holdProfile) return (profile = Completer<DriverKyc>()).future;
    return Future.value(DriverKyc(transmission: transmission));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Keeps captures where they were taken; nothing touches the disk.
class _NoDisk extends DocumentFileStore {
  @override
  Future<String> persist(DocumentKind kind, String sourcePath) async =>
      sourcePath;

  @override
  Future<String?> pathFor(DocumentKind kind) async => null;

  @override
  Future<void> discard(DocumentKind kind) async {}

  @override
  Future<void> discardAll() async {}
}
