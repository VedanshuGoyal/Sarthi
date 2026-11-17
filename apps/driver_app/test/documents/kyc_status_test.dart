import 'dart:io';

import 'package:checks/checks.dart';
import 'package:driver_app/features/documents/data/document_file_store.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/data/kyc_status_store.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/view_model/document_registration_view_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kyc_fakes.dart';

/// Answers [load] with [kyc], or throws [failWith].
class _Repository implements DriverKycRepository {
  _Repository({this.kyc = const DriverKyc(), this.failWith});

  DriverKyc kyc;
  KycException? failWith;

  @override
  Future<DriverKyc> load() async {
    final failure = failWith;
    if (failure != null) throw failure;
    return kyc;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _offline = KycException(
  "Can't reach the server. Check your connection and try again.",
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  setUp(() => tempDir = Directory.systemTemp.createTempSync('kyc_status'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<DocumentRegistrationViewModel> restored(
    _Repository repository,
    KycStatusStore store, {
    String driverId = 'd1',
  }) async {
    final vm = DocumentRegistrationViewModel(
      repository: repository,
      files: DocumentFileStore(directory: tempDir),
      statusStore: store,
      driverId: driverId,
    );
    check(vm.isRestoring).isTrue();
    while (vm.isRestoring) {
      await Future<void>.delayed(Duration.zero);
    }
    return vm;
  }

  group('last known KYC status', () {
    test('a verified driver whose first load fails stays verified', () async {
      final vm = await restored(
        _Repository(failWith: _offline),
        MemoryKycStatusStore('d1', KycStatus.verified),
      );
      check(vm.isVerified).isTrue();

      await vm.load();

      check(vm.isVerified).isTrue();
      check(vm.loadFailed).isTrue();
    });

    test("the backend's answer wins, and is what's stored next", () async {
      final store = MemoryKycStatusStore('d1', KycStatus.verified);
      final repository = _Repository(
        kyc: const DriverKyc(status: KycStatus.rejected),
      );
      final vm = await restored(repository, store);

      await vm.load();

      check(vm.isVerified).isFalse();
      check(vm.loadFailed).isFalse();
      check(store.status).equals(KycStatus.rejected);

      // The same answer again isn't rewritten.
      await vm.load();
      check(store.writes).equals(1);
    });

    test("another driver's status doesn't carry over", () async {
      final vm = await restored(
        _Repository(failWith: _offline),
        MemoryKycStatusStore('d1', KycStatus.verified),
        driverId: 'd2',
      );

      await vm.load();

      check(vm.isVerified).isFalse();
      check(vm.loadFailed).isTrue();
    });

    test('a failed load offers a retry, which recovers', () async {
      final repository = _Repository(failWith: _offline);
      final vm = await restored(repository, MemoryKycStatusStore());
      await vm.load();
      check(vm.loadFailed).isTrue();

      repository
        ..failWith = null
        ..kyc = const DriverKyc(status: KycStatus.verified);
      await vm.load();

      check(vm.loadFailed).isFalse();
      check(vm.isVerified).isTrue();
    });
  });

  group('SecureKycStatusStore', () {
    test('reads back only the driver it was stored for', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureKycStatusStore();

      check(await store.read('d1')).isNull();
      await store.write('d1', KycStatus.verified);
      check(await store.read('d1')).equals(KycStatus.verified);
      check(await store.read('d2')).isNull();

      await store.write('d2', KycStatus.submitted);
      check(await store.read('d1')).isNull();
      check(await store.read('d2')).equals(KycStatus.submitted);
    });
  });
}
