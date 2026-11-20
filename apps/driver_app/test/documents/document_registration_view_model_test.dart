import 'dart:async';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/documents/data/document_file_store.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/document_providers.dart';
import 'package:driver_app/features/documents/domain/digilocker_session.dart';
import 'package:driver_app/features/documents/domain/document_kind.dart';
import 'package:driver_app/features/documents/domain/document_step.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/domain/gender.dart';
import 'package:driver_app/features/documents/domain/vehicle_type.dart';
import 'package:driver_app/features/documents/view_model/document_registration_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('kyc_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  /// The bytes of every test photo.
  const photo = [0xff, 0xd8, 0xff, 0xe0];

  /// A capture standing in for what `image_picker` hands back.
  String writePickedPhoto([String name = 'picked.jpg']) {
    final file = File('${tempDir.path}/$name')..writeAsBytesSync(photo);
    return file.path;
  }

  DocumentRegistrationViewModel viewModel(_FakeKycRepository repository) {
    return DocumentRegistrationViewModel(
      repository: repository,
      files: DocumentFileStore(directory: tempDir),
    );
  }

  group('a load racing a step', () {
    test(
      're-reads instead of dropping an answer a step reply overtook',
      () async {
        final repository = _LoadGatedKycRepository(kyc: _completeKyc);
        final vm = viewModel(repository);

        final first = vm.load(); // held at the gate
        // A licence check lands while that read is in flight…
        check(await vm.verifyDrivingLicense('MH0120210000001')).isTrue();
        // …and meanwhile the reviewer cleared the driver.
        repository.kyc = const DriverKyc(
          status: KycStatus.verified,
          fullName: 'Asha Kumari',
        );
        repository.loadGate.complete();
        await first;
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        check(repository.loads).equals(2);
        check(vm.kyc.status).equals(KycStatus.verified);
      },
    );

    test('a failed load does not report a step that saved as failed', () async {
      final repository = _LoadGatedKycRepository(kyc: _completeKyc)
        ..failLoad = const KycException('offline');
      final vm = viewModel(repository);

      final first = vm.load();
      final saved = vm.verifyDrivingLicense('MH0120210000001');
      repository.loadGate.complete();
      await first;
      check(await saved).isTrue();
      check(vm.error).isNull();
    });
  });

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
    // A typed number proves nothing — the step is done when the backend's
    // check passed, not when the driver filled the field in.
    test(
      'the Aadhar step needs the DigiLocker check, not the number',
      () async {
        final repository = _FakeKycRepository(
          kyc: const DriverKyc(
            fullName: 'Asha Kumari',
            gender: Gender.female,
            aadhaarLast4: '9012',
            uploadedKinds: {DocumentKind.aadhaar},
          ),
        );
        final vm = viewModel(repository);
        await vm.load();

        check(vm.isComplete(DocumentStep.aadhar)).isFalse();

        repository.kyc = DriverKyc(
          aadhaarLast4: '9012',
          aadhaarVerifiedAt: DateTime.utc(2026, 10, 27),
        );
        await vm.load();

        check(vm.isComplete(DocumentStep.aadhar)).isTrue();
      },
    );

    test('the license and bank steps need their checks too', () async {
      final repository = _FakeKycRepository(
        kyc: const DriverKyc(
          drivingLicenseNumber: 'DL0120190012345',
          uploadedKinds: {DocumentKind.drivingLicense},
          bankAccount: BankAccountSummary(
            accountHolderName: 'Asha Kumari',
            accountNumberLast4: '2345',
            ifscCode: 'HDFC0001234',
          ),
        ),
      );
      final vm = viewModel(repository);
      await vm.load();

      check(vm.isComplete(DocumentStep.drivingLicense)).isFalse();
      check(vm.isComplete(DocumentStep.bankDetails)).isFalse();

      repository.kyc = _completeKyc;
      await vm.load();

      check(vm.isComplete(DocumentStep.drivingLicense)).isTrue();
      check(vm.isComplete(DocumentStep.bankDetails)).isTrue();
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
    test(
      'uploads a durable copy, then deletes it once the backend has it',
      () async {
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
        // Sent from the durable copy, not the picker's, which the OS can
        // reclaim; and that copy is gone once the backend has the image.
        final sent = repository.uploadedPaths.single;
        check(sent).not((it) => it.equals(picked));
        check(File(sent).existsSync()).isFalse();
        check(vm.data.capturePathFor(DocumentKind.selfie)).isNull();
      },
    );

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

    // F14: the retry used to copy the stored capture onto itself, which
    // truncates it, so every retry sent an empty file.
    test('a retry sends the photo itself, not an emptied copy', () async {
      final repository = _FakeKycRepository(
        failWith: const KycException('upload failed'),
      );
      final vm = viewModel(repository);
      await vm.capturePhoto(DocumentKind.aadhaar, writePickedPhoto());
      final stored = vm.data.capturePathFor(DocumentKind.aadhaar)!;

      repository.failWith = const KycException('upload failed again');
      await vm.retryUpload(DocumentKind.aadhaar);
      check(File(stored).readAsBytesSync()).deepEquals(photo);

      repository.failWith = null;
      await vm.retryUpload(DocumentKind.aadhaar);

      check(repository.uploadedBytes).deepEquals([photo, photo, photo]);
      check(
        vm.data.uploadStateFor(DocumentKind.aadhaar),
      ).equals(DocumentUploadState.uploaded);
    });

    test(
      'a retake replaces the previous capture rather than piling up',
      () async {
        // Failing uploads, so the captures stay on the phone.
        final repository = _FakeKycRepository(
          failWith: const KycException('upload failed'),
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

  group('a selfie taken while Android killed the app', () {
    test('is uploaded on the next load, once', () async {
      final repository = _FakeKycRepository();
      final lost = writePickedPhoto('lost.jpg');
      var asked = 0;
      final vm = DocumentRegistrationViewModel(
        repository: repository,
        files: DocumentFileStore(directory: tempDir),
        lostCaptures: () async {
          asked++;
          return lost;
        },
      );

      await vm.load();
      await pumpEventQueue();
      await vm.load();
      await pumpEventQueue();

      check(asked).equals(1);
      check(repository.uploaded).deepEquals([DocumentKind.selfie]);
      check(repository.uploadedBytes.single).deepEquals(photo);
    });

    test('nothing lost, nothing sent', () async {
      final repository = _FakeKycRepository();
      final vm = DocumentRegistrationViewModel(
        repository: repository,
        files: DocumentFileStore(directory: tempDir),
        lostCaptures: () async => null,
      );

      await vm.load();
      await pumpEventQueue();

      check(repository.uploaded).isEmpty();
    });
  });

  group('DocumentFileStore', () {
    test('persisting the stored capture again leaves it intact', () async {
      final store = DocumentFileStore(directory: tempDir);
      final stored = await store.persist(
        DocumentKind.selfie,
        writePickedPhoto(),
      );

      final again = await store.persist(DocumentKind.selfie, stored);

      check(again).equals(stored);
      check(
        File(stored).readAsBytesSync(),
      ).deepEquals([0xff, 0xd8, 0xff, 0xe0]);
    });
  });

  group('per driver', () {
    DriverAuthSession session(String id) => DriverAuthSession(
      token: 'tok-$id',
      driver: Driver(id: id, phoneE164: '+919800000001', name: 'Driver $id'),
    );

    test('the next driver on this phone starts unverified', () async {
      final repository = _FakeKycRepository(
        kyc: const DriverKyc(status: KycStatus.verified, fullName: 'Asha'),
      );
      final container = ProviderContainer(
        overrides: [
          driverSessionStorageProvider.overrideWithValue(
            _MemorySessionStorage(session('d1')),
          ),
          driverKycRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(driverAuthControllerProvider.future);

      final first = container.read(documentRegistrationViewModelProvider);
      await first.setVehicleType(VehicleType.both);
      check(first.isVerified).isTrue();

      final auth = container.read(driverAuthControllerProvider.notifier);
      await auth.signOut();
      await auth.signIn(session('d2'));

      final second = container.read(documentRegistrationViewModelProvider);
      check(identical(first, second)).isFalse();
      check(second.isVerified).isFalse();
      check(second.kyc.fullName).isEmpty();
    });

    test('a request settling after a sign-out notifies no one', () async {
      final repository = _GatedKycRepository(kyc: _completeKyc);
      final vm = viewModel(repository);

      final verifying = vm.verifyDrivingLicense('MP0920190012345');
      // Signing out replaces the view model while the check is in flight.
      vm.dispose();
      repository.gate.complete();

      check(await verifying).isTrue();
    });
  });

  group('double submits', () {
    test('a retake while the photo is still uploading is ignored', () async {
      final repository = _FakeKycRepository(
        kyc: const DriverKyc(uploadedKinds: {DocumentKind.selfie}),
      );
      final vm = viewModel(repository);

      await Future.wait([
        vm.capturePhoto(DocumentKind.selfie, writePickedPhoto('first.jpg')),
        vm.capturePhoto(DocumentKind.selfie, writePickedPhoto('second.jpg')),
      ]);

      check(repository.uploaded).deepEquals([DocumentKind.selfie]);
      check(
        vm.data.uploadStateFor(DocumentKind.selfie),
      ).equals(DocumentUploadState.uploaded);

      // Once it has landed, a retake goes through again.
      await vm.capturePhoto(DocumentKind.selfie, writePickedPhoto('third.jpg'));
      check(repository.uploaded).length.equals(2);
    });

    test('a capture that cannot be stored fails instead of hanging', () async {
      final repository = _FakeKycRepository();
      final vm = viewModel(repository);

      await vm.capturePhoto(DocumentKind.selfie, '${tempDir.path}/gone.jpg');

      check(
        vm.data.uploadStateFor(DocumentKind.selfie),
      ).equals(DocumentUploadState.failed);
      check(vm.error).isNotNull();
      check(repository.uploaded).isEmpty();
    });

    test('a second check while one is in flight is not sent', () async {
      final repository = _FakeKycRepository(kyc: _completeKyc);
      final vm = viewModel(repository);

      final results = await Future.wait([
        vm.verifyDrivingLicense('MP0920190012345'),
        vm.verifyDrivingLicense('MP0920190012345'),
      ]);

      check(repository.verifiedLicenses).length.equals(1);
      check(results).deepEquals([true, false]);
      check(vm.isSaving).isFalse();
      check(vm.error).isNull();
    });
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

    test('isVerified follows the backend status, not local progress', () async {
      final repository = _FakeKycRepository(kyc: _completeKyc);
      final vm = viewModel(repository);
      await vm.load();

      check(vm.isVerified).isFalse();

      repository.kyc = const DriverKyc(status: KycStatus.verified);
      await vm.submit();

      check(vm.isVerified).isTrue();
      check(vm.isUnderReview).isFalse();
    });

    // A mismatch the backend can't settle on its own goes to a person; the
    // driver stays out of Home until they clear it.
    test('a submission sent for review is not verified', () async {
      final repository = _FakeKycRepository(kyc: _completeKyc);
      final vm = viewModel(repository);

      repository.kyc = const DriverKyc(
        status: KycStatus.submitted,
        reviewNote: 'Name on the bank account differs from Aadhaar',
      );
      await vm.submit();

      check(vm.isVerified).isFalse();
      check(vm.isUnderReview).isTrue();
      check(vm.kyc.reviewNote).isNotNull().contains('bank account');
    });
  });

  group('DigiLocker', () {
    test('startDigiLocker hands back the session to open', () async {
      final repository = _FakeKycRepository();
      final vm = viewModel(repository);

      final session = await vm.startDigiLocker();

      check(
        session,
      ).isNotNull().has((s) => s.url.host, 'host').equals('digilocker.test');
      check(vm.isSaving).isFalse();
      check(vm.error).isNull();
    });

    test('startDigiLocker surfaces a refusal', () async {
      final repository = _FakeKycRepository(
        failWith: const KycException(
          'Too many attempts today',
          code: 'too_many_attempts',
        ),
      );
      final vm = viewModel(repository);

      final session = await vm.startDigiLocker();

      check(session).isNull();
      check(vm.errorCode).equals('too_many_attempts');
    });

    test('completing too early reports pending, then succeeds', () async {
      final repository = _FakeKycRepository(
        failWith: const KycException(
          "DigiLocker isn't finished yet",
          code: 'verification_pending',
        ),
      );
      final vm = viewModel(repository);

      check(await vm.completeDigiLocker()).isFalse();
      check(vm.errorCode).equals('verification_pending');
      check(vm.isComplete(DocumentStep.aadhar)).isFalse();

      repository
        ..failWith = null
        ..kyc = DriverKyc(
          fullName: 'Asha Kumari',
          aadhaarLast4: '9012',
          aadhaarVerifiedAt: DateTime.utc(2026, 10, 27),
        );

      check(await vm.completeDigiLocker()).isTrue();
      check(vm.errorCode).isNull();
      check(vm.error).isNull();
      check(vm.isComplete(DocumentStep.aadhar)).isTrue();
    });
  });

  group('verifyDrivingLicense', () {
    test('folds the verified license in', () async {
      final repository = _FakeKycRepository(
        kyc: DriverKyc(
          drivingLicenseNumber: 'DL0120190012345',
          licenseVerifiedAt: DateTime.utc(2026, 10, 27),
          licenseName: 'ASHA KUMARI',
        ),
      );
      final vm = viewModel(repository);

      check(await vm.verifyDrivingLicense('DL0120190012345')).isTrue();

      check(repository.verifiedLicenses).deepEquals(['DL0120190012345']);
      check(vm.isComplete(DocumentStep.drivingLicense)).isTrue();
    });

    test('surfaces a license that was not found', () async {
      final repository = _FakeKycRepository(
        failWith: const KycException(
          "We couldn't find this license",
          code: 'license_not_found',
        ),
      );
      final vm = viewModel(repository);

      check(await vm.verifyDrivingLicense('DL0120190012345')).isFalse();

      check(vm.errorCode).equals('license_not_found');
      check(vm.isComplete(DocumentStep.drivingLicense)).isFalse();
    });
  });
}

/// A driver who has finished every backend-tracked step.
final _completeKyc = DriverKyc(
  fullName: 'Asha Kumari',
  gender: Gender.female,
  transmission: VehicleType.both,
  aadhaarLast4: '9012',
  drivingLicenseNumber: 'DL0120190012345',
  uploadedKinds: const {DocumentKind.selfie},
  aadhaarVerifiedAt: DateTime.utc(2026, 10, 27),
  licenseVerifiedAt: DateTime.utc(2026, 10, 27),
  bankAccount: BankAccountSummary(
    accountHolderName: 'Asha Kumari',
    accountNumberLast4: '2345',
    ifscCode: 'HDFC0001234',
    verifiedAt: DateTime.utc(2026, 10, 27),
    verifiedName: 'ASHA KUMARI',
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

  /// The bytes of each upload's file, read when it was sent.
  final List<List<int>> uploadedBytes = [];

  /// The file each upload was sent from.
  final List<String> uploadedPaths = [];

  /// Every license number sent for checking.
  final List<String> verifiedLicenses = [];

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
    uploadedBytes.add(File(path).readAsBytesSync());
    uploadedPaths.add(path);
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
  Future<DigiLockerSession> startDigiLocker() async {
    _respond();
    return DigiLockerSession(url: Uri.parse('https://digilocker.test/start'));
  }

  @override
  Future<DriverKyc> completeDigiLocker() async => _respond();

  @override
  Future<DriverKyc> verifyDrivingLicense(String number) async {
    verifiedLicenses.add(number);
    return _respond();
  }

  @override
  Future<DriverKyc> submit() async => _respond();
}

/// A [_FakeKycRepository] whose licence check waits for [gate].
class _GatedKycRepository extends _FakeKycRepository {
  _GatedKycRepository({super.kyc});

  final gate = Completer<void>();

  @override
  Future<DriverKyc> verifyDrivingLicense(String number) async {
    await gate.future;
    return super.verifyDrivingLicense(number);
  }
}

/// A [_FakeKycRepository] whose first load waits for [loadGate] and then,
/// with [failLoad] set, fails.
class _LoadGatedKycRepository extends _FakeKycRepository {
  _LoadGatedKycRepository({super.kyc});

  final loadGate = Completer<void>();
  KycException? failLoad;
  int loads = 0;

  @override
  Future<DriverKyc> load() async {
    loads++;
    final stale = kyc;
    if (loads == 1) {
      await loadGate.future;
      if (failLoad case final failure?) throw failure;
      return stale; // read before the gate opened
    }
    return super.load();
  }
}

/// A session store held in memory, starting with [_session].
class _MemorySessionStorage implements DriverSessionStorage {
  _MemorySessionStorage(this._session);

  DriverAuthSession? _session;

  @override
  Future<DriverAuthSession?> read() async => _session;

  @override
  Future<void> write(DriverAuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
