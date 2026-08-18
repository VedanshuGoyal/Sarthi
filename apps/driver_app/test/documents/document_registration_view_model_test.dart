import 'dart:io';

import 'package:checks/checks.dart';
import 'package:driver_app/features/documents/data/document_file_store.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/domain/document_kind.dart';
import 'package:driver_app/features/documents/domain/document_step.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/domain/gender.dart';
import 'package:driver_app/features/documents/domain/vehicle_type.dart';
import 'package:driver_app/features/documents/view_model/document_registration_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('kyc_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  /// A capture standing in for what `image_picker` hands back.
  String writePickedPhoto([String name = 'picked.jpg']) {
    final file = File('${tempDir.path}/$name')
      ..writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0]);
    return file.path;
  }

  DocumentRegistrationViewModel viewModel(_FakeKycRepository repository) {
    return DocumentRegistrationViewModel(
      repository: repository,
      files: DocumentFileStore(directory: tempDir),
    );
  }

  group('load', () {
    test('takes its progress from the backend', () async {
      final repository = _FakeKycRepository(kyc: _completeKyc);
      final vm = viewModel(repository);

      await vm.load();

      check(vm.isLoading).isFalse();
      check(vm.kyc.fullName).equals('Asha Kumari');
      check(vm.isComplete(DocumentStep.vehicleType)).isTrue();
      check(vm.isComplete(DocumentStep.aadhar)).isTrue();
      // Permissions are OS grants, never restored from the backend.
      check(vm.isComplete(DocumentStep.permissions)).isFalse();
    });

    test('surfaces a load failure instead of showing an empty flow', () async {
      final repository = _FakeKycRepository(
        failWith: const KycException('server is down'),
      );
      final vm = viewModel(repository);

      await vm.load();

      check(vm.error).equals('server is down');
      check(vm.isLoading).isFalse();
    });
  });

  group('step completion', () {
    // A photo sitting on the phone proves nothing — the step is done when the
    // backend has the image, not when the camera closed.
    test('a photo step needs the upload, not just the capture', () async {
      final repository = _FakeKycRepository(
        kyc: const DriverKyc(
          fullName: 'Asha Kumari',
          gender: Gender.female,
          aadhaarLast4: '9012',
        ),
      );
      final vm = viewModel(repository);
      await vm.load();

      check(vm.isComplete(DocumentStep.aadhar)).isFalse();
    });

    test('unlocks a step only once the one before it is done', () async {
      final repository = _FakeKycRepository(
        kyc: const DriverKyc(transmission: VehicleType.both),
      );
      final vm = viewModel(repository);
      await vm.load();

      check(vm.isUnlocked(DocumentStep.vehicleType)).isTrue();
      check(vm.isUnlocked(DocumentStep.photoAndName)).isTrue();
      check(vm.isUnlocked(DocumentStep.aadhar)).isFalse();
    });
  });

  group('capturePhoto', () {
    test('copies the capture somewhere durable and uploads it', () async {
      final repository = _FakeKycRepository(
        kyc: const DriverKyc(uploadedKinds: {DocumentKind.selfie}),
      );
      final vm = viewModel(repository);
      final picked = writePickedPhoto();

      await vm.capturePhoto(DocumentKind.selfie, picked);

      check(repository.uploaded).unorderedEquals([DocumentKind.selfie]);
      check(
        vm.data.uploadStateFor(DocumentKind.selfie),
      ).equals(DocumentUploadState.uploaded);

      // The stored path must not be the picker's, which the OS can reclaim.
      final stored = vm.data.capturePathFor(DocumentKind.selfie);
      check(stored).isNotNull().not((it) => it.equals(picked));
      check(File(stored!).existsSync()).isTrue();
    });

    test('marks the upload failed and keeps the file for a retry', () async {
      final repository = _FakeKycRepository(
        failWith: const KycException('upload rejected'),
      );
      final vm = viewModel(repository);

      await vm.capturePhoto(DocumentKind.aadhaar, writePickedPhoto());

      check(
        vm.data.uploadStateFor(DocumentKind.aadhaar),
      ).equals(DocumentUploadState.failed);
      check(vm.error).equals('upload rejected');
      // The capture survives, or the driver would have to reshoot it.
      check(vm.data.capturePathFor(DocumentKind.aadhaar)).isNotNull();
    });

    test('retryUpload re-sends the capture already on disk', () async {
      final repository = _FakeKycRepository(
        failWith: const KycException('upload rejected'),
      );
      final vm = viewModel(repository);
      await vm.capturePhoto(DocumentKind.aadhaar, writePickedPhoto());

      repository
        ..failWith = null
        ..kyc = const DriverKyc(uploadedKinds: {DocumentKind.aadhaar});
      await vm.retryUpload(DocumentKind.aadhaar);

      check(
        vm.data.uploadStateFor(DocumentKind.aadhaar),
      ).equals(DocumentUploadState.uploaded);
      check(
        repository.uploaded,
      ).unorderedEquals([DocumentKind.aadhaar, DocumentKind.aadhaar]);
    });

    test(
      'a retake replaces the previous capture rather than piling up',
      () async {
        final repository = _FakeKycRepository(
          kyc: const DriverKyc(uploadedKinds: {DocumentKind.aadhaar}),
        );
        final vm = viewModel(repository);

        await vm.capturePhoto(
          DocumentKind.aadhaar,
          writePickedPhoto('first.jpg'),
        );
        final first = vm.data.capturePathFor(DocumentKind.aadhaar);
        await vm.capturePhoto(
          DocumentKind.aadhaar,
          writePickedPhoto('second.jpg'),
        );

        check(vm.data.capturePathFor(DocumentKind.aadhaar)).equals(first);
        final captures = Directory(
          '${tempDir.path}/${DocumentFileStore.folderName}',
        ).listSync();
        check(captures).length.equals(1);
      },
    );
  });

  group('saving a step', () {
    test('folds the backend response in as the new truth', () async {
      final repository = _FakeKycRepository(
        kyc: const DriverKyc(transmission: VehicleType.manual),
      );
      final vm = viewModel(repository);

      await vm.setVehicleType(VehicleType.manual);

      check(vm.kyc.transmission).equals(VehicleType.manual);
      check(vm.isSaving).isFalse();
      check(vm.error).isNull();
    });

    test('surfaces a rejection and leaves the step incomplete', () async {
      final repository = _FakeKycRepository(
        failWith: const KycException('this Aadhaar is already registered'),
      );
      final vm = viewModel(repository);

      await vm.setAadhar(number: '123456789012');

      check(vm.error).equals('this Aadhaar is already registered');
      check(vm.isComplete(DocumentStep.aadhar)).isFalse();
      check(vm.isSaving).isFalse();
    });
  });

  group('submit', () {
    test('wipes the on-device captures once the backend accepts', () async {
      final repository = _FakeKycRepository(kyc: _completeKyc);
      final vm = viewModel(repository);
      await vm.capturePhoto(DocumentKind.aadhaar, writePickedPhoto());
      await vm.capturePhoto(DocumentKind.selfie, writePickedPhoto('two.jpg'));

      final submitted = await vm.submit();

      check(submitted).isTrue();
      check(vm.data.capturePathFor(DocumentKind.aadhaar)).isNull();
      // An identity document has no business outliving its upload.
      final captureDir = Directory(
        '${tempDir.path}/${DocumentFileStore.folderName}',
      );
      check(captureDir.listSync()).isEmpty();
    });

    test('keeps the captures when the backend refuses', () async {
      final repository = _FakeKycRepository(
        failWith: const KycException('document verification is incomplete'),
      );
      final vm = viewModel(repository);
      await vm.capturePhoto(DocumentKind.aadhaar, writePickedPhoto());

      final submitted = await vm.submit();

      check(submitted).isFalse();
      check(vm.error).isNotNull().contains('incomplete');
      check(vm.data.capturePathFor(DocumentKind.aadhaar)).isNotNull();
    });

    test(
      'isSubmitted follows the backend status, not local progress',
      () async {
        final repository = _FakeKycRepository(kyc: _completeKyc);
        final vm = viewModel(repository);
        await vm.load();

        check(vm.isSubmitted).isFalse();

        repository.kyc = const DriverKyc(status: KycStatus.submitted);
        await vm.submit();

        check(vm.isSubmitted).isTrue();
      },
    );
  });
}

/// A driver who has finished every backend-tracked step.
const _completeKyc = DriverKyc(
  fullName: 'Asha Kumari',
  gender: Gender.female,
  transmission: VehicleType.both,
  aadhaarLast4: '9012',
  drivingLicenseNumber: 'DL0120190012345',
  uploadedKinds: {
    DocumentKind.selfie,
    DocumentKind.aadhaar,
    DocumentKind.drivingLicense,
  },
  bankAccount: BankAccountSummary(
    accountHolderName: 'Asha Kumari',
    accountNumberLast4: '2345',
    ifscCode: 'HDFC0001234',
  ),
);

/// Stands in for the backend: returns [kyc] from every call, or throws
/// [failWith] when set.
class _FakeKycRepository implements DriverKycRepository {
  _FakeKycRepository({this.kyc = const DriverKyc(), this.failWith});

  DriverKyc kyc;
  KycException? failWith;

  /// Every kind uploaded, in order, including repeats from a retry.
  final List<DocumentKind> uploaded = [];

  DriverKyc _respond() {
    final failure = failWith;
    if (failure != null) throw failure;
    return kyc;
  }

  @override
  Future<DriverKyc> load() async => _respond();

  @override
  Future<DriverKyc> uploadDocument(DocumentKind kind, String path) async {
    uploaded.add(kind);
    return _respond();
  }

  @override
  Future<DriverKyc> updateProfile({
    VehicleType? transmission,
    String? fullName,
    DateTime? dateOfBirth,
    Gender? gender,
    String? aadhaarNumber,
    String? drivingLicenseNumber,
  }) async => _respond();

  @override
  Future<DriverKyc> setBankAccount({
    required String accountHolderName,
    required String accountNumber,
    required String ifscCode,
  }) async => _respond();

  @override
  Future<DriverKyc> submit() async => _respond();
}
