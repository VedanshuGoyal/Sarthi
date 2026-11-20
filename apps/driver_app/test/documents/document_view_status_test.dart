import 'package:checks/checks.dart';
import 'package:driver_app/core/location_providers.dart';
import 'package:driver_app/core/services/push_service.dart';
import 'package:driver_app/features/account/account_providers.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/documents/data/document_file_store.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/data/permission_grants.dart';
import 'package:driver_app/features/documents/document_providers.dart';
import 'package:driver_app/features/documents/domain/document_kind.dart';
import 'package:driver_app/features/documents/domain/document_step.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/domain/gender.dart';
import 'package:driver_app/features/documents/domain/vehicle_type.dart';
import 'package:driver_app/features/documents/view/document_view_screen.dart';
import 'package:driver_app/features/documents/view_model/document_registration_view_model.dart';
import 'package:driver_app/features/notifications/notification_providers.dart';
import 'package:driver_app/features/rides/rides_providers.dart';
import 'package:driver_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../rides/fakes.dart';

const _driver = Driver(id: 'd1', phoneE164: '+919800000001', name: 'Asha');

/// Every step the backend checks is done; [status] is where review stands.
DriverKyc _kyc(
  KycStatus status, {
  bool bankVerified = true,
  String? reviewNote,
  DateTime? submittedAt,
}) => DriverKyc(
  status: status,
  fullName: 'Asha Kumari',
  dateOfBirth: DateTime(1995, 3, 2),
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
    verifiedAt: bankVerified ? DateTime.utc(2026, 10, 27) : null,
  ),
  reviewNote: reviewNote,
  submittedAt: submittedAt,
);

const PermissionGrants _allGranted = (
  overlay: true,
  backgroundLocation: true,
  battery: true,
);

const PermissionGrants _noneGranted = (
  overlay: false,
  backgroundLocation: false,
  battery: false,
);

void main() {
  late _KycRepository repository;
  late PermissionGrants? grants;
  late DateTime now;

  setUp(() {
    repository = _KycRepository();
    grants = _noneGranted;
    now = DateTime(2026, 11, 21, 9);
  });

  DocumentRegistrationViewModel viewModel() => DocumentRegistrationViewModel(
    repository: repository,
    files: _NoCaptures(),
    permissionGrants: () async => grants,
    now: () => now,
  );

  /// Backgrounds the app and brings it back, as the platform reports it.
  Future<void> leaveAndReturn(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  group('OS permission grants', () {
    test('already granted, they tick the permissions step on load', () async {
      repository.kyc = _kyc(KycStatus.submitted);
      grants = _allGranted;
      final vm = viewModel();

      await vm.load();

      check(vm.isComplete(DocumentStep.permissions)).isTrue();
      check(vm.completedCount).equals(DocumentStep.values.length);
    });

    test('re-reading them un-ticks one turned off, and says so', () async {
      repository.kyc = _kyc(KycStatus.submitted);
      grants = _allGranted;
      final vm = viewModel();
      await vm.load();
      var notified = 0;
      vm.addListener(() => notified++);

      grants = (overlay: true, backgroundLocation: false, battery: true);
      await vm.refreshPermissionGrants();

      check(vm.isComplete(DocumentStep.permissions)).isFalse();
      check(notified).equals(1);

      // Unchanged: nothing to redraw.
      await vm.refreshPermissionGrants();
      check(notified).equals(1);
    });

    test('when the OS cannot be asked, the step keeps what it had', () async {
      repository.kyc = _kyc(KycStatus.submitted);
      final vm = viewModel();
      vm.setPermissions(
        overlayGranted: true,
        backgroundLocationGranted: true,
        batteryUnrestricted: true,
      );

      grants = null;
      await vm.load();

      check(vm.isComplete(DocumentStep.permissions)).isTrue();
    });
  });

  group('locked steps', () {
    test(
      'a finished step never looks locked behind an unfinished one',
      () async {
        repository.kyc = _kyc(KycStatus.submitted);
        final vm = viewModel();
        await vm.load();

        check(vm.isComplete(DocumentStep.permissions)).isFalse();
        check(vm.isComplete(DocumentStep.bankDetails)).isTrue();
        check(vm.isUnlocked(DocumentStep.bankDetails)).isTrue();
      },
    );

    test('an unfinished step after an unfinished one stays locked', () async {
      repository.kyc = _kyc(KycStatus.incomplete, bankVerified: false);
      final vm = viewModel();
      await vm.load();

      check(vm.isUnlocked(DocumentStep.bankDetails)).isFalse();
    });

    test('a verified driver can open every step', () async {
      repository.kyc = _kyc(KycStatus.verified, bankVerified: false);
      final vm = viewModel();
      await vm.load();

      for (final step in DocumentStep.values) {
        check(vm.isUnlocked(step)).isTrue();
      }
    });
  });

  group('the Document View', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pushServiceProvider.overrideWithValue(PushService.off()),
            kycCaptureStoreProvider.overrideWithValue(_NoCaptures()),
            ridesRepositoryProvider.overrideWithValue(FakeRidesRepository()),
            locationServiceProvider.overrideWithValue(FakeLocationService()),
            driverSessionStorageProvider.overrideWithValue(_SessionStorage()),
            documentRegistrationViewModelProvider.overrideWith(
              (ref) => viewModel(),
            ),
          ],
          child: MaterialApp(
            theme: SkylineTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DocumentViewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Iterable<Element> text(String s) => find.text(s).evaluate();
    Iterable<Element> locks() => find.byIcon(Icons.lock_outline).evaluate();

    testWidgets('a verified driver sees they are cleared, not a to-do list', (
      tester,
    ) async {
      // Permissions not granted on this phone: still nothing to submit.
      repository.kyc = _kyc(KycStatus.verified);
      await pump(tester);

      check(text("You're verified")).isNotEmpty();
      check(text('Cleared to drive')).isNotEmpty();
      check(
        text('Aadhaar XXXX XXXX 9012 · verified with DigiLocker'),
      ).isNotEmpty();
      check(text('Driving licence DL0120190012345 · verified')).isNotEmpty();
      check(
        text('Bank account •••• 2345 · verified with your bank'),
      ).isNotEmpty();
      check(text('5/6')).isEmpty();
      check(text('Submit for verification')).isEmpty();
      check(text('Check again')).isEmpty();
      check(text('Complete your registration')).isEmpty();
      check(locks()).isEmpty();
      check(text('Aadhaar Card')).isNotEmpty();
    });

    testWidgets('under review, granted permissions count without opening '
        'the step', (tester) async {
      repository.kyc = _kyc(
        KycStatus.submitted,
        reviewNote: 'Your selfie is being compared by a person.',
        submittedAt: DateTime(2026, 11, 20, 10),
      );
      grants = _allGranted;
      await pump(tester);

      check(text('Under review')).isNotEmpty();
      check(text('Waiting on a reviewer')).isNotEmpty();
      check(text('Your selfie is being compared by a person.')).isNotEmpty();
      check(text('Sent 20 Nov 2026')).isNotEmpty();
      check(text('6/6')).isNotEmpty();
      check(text('Check again')).isNotEmpty();
      check(text('Submit for verification')).isEmpty();
    });

    testWidgets('permissions granted in settings tick when the driver comes '
        'back, and a verified bank never shows a lock', (tester) async {
      repository.kyc = _kyc(KycStatus.submitted);
      await pump(tester);

      check(text('5/6')).isNotEmpty();
      check(locks()).isEmpty();

      grants = _allGranted;
      await leaveAndReturn(tester);

      check(text('6/6')).isNotEmpty();
    });

    testWidgets('sent back: the reviewer\'s note, and a way to resubmit', (
      tester,
    ) async {
      repository.kyc = _kyc(
        KycStatus.rejected,
        reviewNote: 'The selfie is blurred.',
      );
      grants = _allGranted;
      await pump(tester);

      check(text('Some details need fixing')).isNotEmpty();
      check(text('Sent back by a reviewer')).isNotEmpty();
      check(text('The selfie is blurred.')).isNotEmpty();
      check(text('Submit for verification')).isNotEmpty();
    });

    testWidgets('mid-flow, coming back re-reads only the OS grants', (
      tester,
    ) async {
      repository.kyc = _kyc(KycStatus.incomplete, bankVerified: false);
      await pump(tester);
      final loads = repository.loads;
      now = now.add(const Duration(minutes: 1));

      await leaveAndReturn(tester);

      check(repository.loads).equals(loads);
    });

    testWidgets('waiting on a reviewer, coming back re-reads the record — '
        'not again straight after', (tester) async {
      repository.kyc = _kyc(KycStatus.submitted);
      await pump(tester);
      final loads = repository.loads;

      // Just opened: the record is fresh.
      await leaveAndReturn(tester);
      check(repository.loads).equals(loads);

      now = now.add(const Duration(minutes: 1));
      repository.kyc = _kyc(KycStatus.verified);
      await leaveAndReturn(tester);
      check(repository.loads).equals(loads + 1);
      check(find.text("You're verified").evaluate()).isNotEmpty();

      now = now.add(const Duration(seconds: 3));
      await leaveAndReturn(tester);
      check(repository.loads).equals(loads + 1);
    });

    testWidgets('a status from a newer server asks to check again instead of '
        'redoing steps', (tester) async {
      repository.kyc = _kyc(KycStatus.unknown);
      grants = _allGranted;
      await pump(tester);

      check(text("We can't show your status")).isNotEmpty();
      check(text('Status not recognised')).isNotEmpty();
      check(text('Submit for verification')).isEmpty();

      final loads = repository.loads;
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      check(repository.loads).equals(loads + 1);
    });
  });
}

class _KycRepository implements DriverKycRepository {
  DriverKyc kyc = const DriverKyc();
  int loads = 0;

  @override
  Future<DriverKyc> load() async {
    loads++;
    return kyc;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No captures on the device, and no disk I/O (which would never finish
/// inside a widget test's fake clock).
class _NoCaptures extends DocumentFileStore {
  @override
  Future<String?> pathFor(DocumentKind kind) async => null;

  @override
  Future<void> discard(DocumentKind kind) async {}

  @override
  Future<void> discardAll() async {}
}

class _SessionStorage implements DriverSessionStorage {
  @override
  Future<DriverAuthSession?> read() async =>
      const DriverAuthSession(token: 'tok', driver: _driver);

  @override
  Future<void> write(DriverAuthSession session) async {}

  @override
  Future<void> clear() async {}
}
