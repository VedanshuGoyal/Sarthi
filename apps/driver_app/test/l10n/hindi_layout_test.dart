// Pumps the widest screens in Hindi on narrow phones and fails on any
// layout exception (a RenderFlex overflow, an unbounded box). Hindi runs
// longer than English, and the test font draws every character — vowel
// signs included — a full em wide, so this is stricter than a real phone.

import 'package:checks/checks.dart';
import 'package:driver_app/core/location_providers.dart';
import 'package:driver_app/core/refresh_throttle.dart';
import 'package:driver_app/core/services/push_service.dart';
import 'package:driver_app/features/account/account_providers.dart';
import 'package:driver_app/features/account/view/account_panel.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/auth/view/registration_screen.dart';
import 'package:driver_app/features/documents/data/document_file_store.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/document_providers.dart';
import 'package:driver_app/features/documents/domain/document_kind.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/domain/gender.dart';
import 'package:driver_app/features/documents/domain/vehicle_type.dart';
import 'package:driver_app/features/documents/view/aadhar_step.dart';
import 'package:driver_app/features/documents/view/bank_details_step.dart';
import 'package:driver_app/features/documents/view/document_view_screen.dart';
import 'package:driver_app/features/documents/view/driving_license_step.dart';
import 'package:driver_app/features/documents/view/permissions_step.dart';
import 'package:driver_app/features/documents/view/photo_and_name_step.dart';
import 'package:driver_app/features/documents/view/vehicle_type_step.dart';
import 'package:driver_app/features/documents/view_model/document_registration_view_model.dart';
import 'package:driver_app/features/home/view/driver_home_shell.dart';
import 'package:driver_app/features/home/view/start_driving_screen.dart';
import 'package:driver_app/features/language/data/language_repository.dart';
import 'package:driver_app/features/language/domain/app_language.dart';
import 'package:driver_app/features/language/language_providers.dart';
import 'package:driver_app/features/notifications/notification_providers.dart';
import 'package:driver_app/features/rides/domain/payout.dart';
import 'package:driver_app/features/rides/domain/ride.dart';
import 'package:driver_app/features/rides/rides_providers.dart';
import 'package:driver_app/features/rides/view/earnings_panel.dart';
import 'package:driver_app/features/rides/view/ride_detail_screen.dart';
import 'package:driver_app/features/rides/view/rides_panel.dart';
import 'package:driver_app/features/rides/view/widgets/ride_widgets.dart';
import 'package:driver_app/features/update/view/update_required_screen.dart';
import 'package:driver_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../rides/fakes.dart';

const _driver = Driver(
  id: 'd1',
  phoneE164: '+919800000001',
  name: 'Rameshwar Prasad Chaurasia',
);

/// A long-named driver with every KYC step done; [status] is where review
/// stands.
DriverKyc _kyc(KycStatus status, {String? reviewNote}) => DriverKyc(
  status: status,
  fullName: 'Rameshwar Prasad Chaurasia',
  dateOfBirth: DateTime(1988, 12, 2),
  gender: Gender.male,
  transmission: VehicleType.both,
  aadhaarLast4: '9012',
  drivingLicenseNumber: 'UP1420190012345',
  uploadedKinds: const {DocumentKind.selfie},
  aadhaarVerifiedAt: DateTime.utc(2026, 10, 27),
  licenseVerifiedAt: DateTime.utc(2026, 10, 27),
  licenseName: 'RAMESHWAR PRASAD CHAURASIA',
  licenseValidUntil: DateTime(2039, 12, 1),
  licenseClasses: const ['LMV', 'LMV-TR', 'MCWG'],
  bankAccount: BankAccountSummary(
    accountHolderName: 'Rameshwar Prasad Chaurasia',
    accountNumberLast4: '2345',
    ifscCode: 'PUNB0123400',
    verifiedAt: DateTime.utc(2026, 10, 27),
  ),
  reviewNote: reviewNote,
  submittedAt: DateTime(2026, 11, 20, 18),
);

/// A multi-stop ride with long places, for the widest ride rows.
Ride _multiStop({String status = 'accepted', bool withCustomer = true}) =>
    Ride.tryParse({
      ...rideJson(id: 'm1', status: status, withCustomer: withCustomer),
      'tripType': 'multiStop',
      'stops': [
        for (final (i, place) in const [
          'DLF Cyber Hub, DLF Cyber City, DLF Phase 2, Sector 24, Gurugram',
          'Ambience Mall, National Highway 48, Ambience Island, Gurugram',
          'Indira Gandhi International Airport Terminal 3, New Delhi',
        ].indexed)
          {
            'place': {'address': place, 'lat': 28.5, 'lng': 77.1},
            'task': 'Pick up a parcel from the reception desk',
            'departBy': '2026-10-26T1${i + 1}:00:00+05:30',
          },
      ],
    })!;

class _KycRepository implements DriverKycRepository {
  DriverKyc kyc = const DriverKyc();

  @override
  Future<DriverKyc> load() async => kyc;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

class _Languages implements LanguageRepository {
  @override
  Future<AppLanguage> read() async => AppLanguage.hindi;
  @override
  Future<void> write(AppLanguage language) async {}
}

void main() {
  late FakeRidesRepository rides;
  late _KycRepository kyc;
  final now = DateTime(2026, 10, 26, 8);

  setUp(() {
    kyc = _KycRepository();
    rides = FakeRidesRepository()
      ..openRides = [
        _multiStop(status: 'requested', withCustomer: false),
        ride(id: 'o2', approximate: true),
      ]
      ..mine = [
        _multiStop(),
        ride(
          id: 'a2',
          status: 'arrived',
          noShowAt: '2026-10-26T09:15:00+05:30',
        ),
        ride(
          id: 'c1',
          status: 'completed',
          paymentStatus: 'paid',
          sharePaise: 29580,
          bookedFarePaise: 51000,
          farePaise: 34000,
        ),
        ride(
          id: 'x1',
          status: 'cancelled',
          cancelledBy: 'customer',
          cancelReason: 'Plans changed, will book again next week',
          cancellationFeePaise: 5000,
          paymentStatus: 'due',
        ),
      ]
      ..summary = const Earnings(
        today: EarningsPeriod(
          farePaise: 12345600,
          rides: 12,
          netPaise: 10740672,
        ),
        week: EarningsPeriod(
          farePaise: 98765400,
          rides: 88,
          netPaise: 85925898,
        ),
        month: EarningsPeriod(
          farePaise: 98765400,
          rides: 88,
          netPaise: 85925898,
        ),
        total: EarningsPeriod(
          farePaise: 1234567800,
          rides: 1234,
          netPaise: 1074073986,
        ),
        rating: EarningsRating(average: 4.87, count: 1234),
        payments: DriverPayments(
          awaitingCustomerPaise: 1234500,
          awaitingCustomerRides: 11,
          duePaise: 9876500,
          dueRides: 21,
          paidOutPaise: 123456700,
        ),
      )
      ..payoutList = [
        Payout(
          id: 'p1',
          amountPaise: 9876500,
          rides: 21,
          reference: 'UTR-HDFCN52026112012345678',
          createdAt: DateTime(2026, 11, 10, 12),
        ),
      ];
  });
  tearDown(L10n.reset);

  /// Pumps [home] in Hindi at [width] × [height] logical pixels.
  Future<void> pumpHindi(
    WidgetTester tester,
    Widget home, {
    required double width,
    double height = 2400,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          ridesRepositoryProvider.overrideWithValue(rides),
          pushServiceProvider.overrideWithValue(PushService.off()),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          driverSessionStorageProvider.overrideWithValue(_SessionStorage()),
          kycCaptureStoreProvider.overrideWithValue(_NoCaptures()),
          languageRepositoryProvider.overrideWithValue(_Languages()),
          documentRegistrationViewModelProvider.overrideWith(
            (ref) => DocumentRegistrationViewModel(
              repository: kyc,
              files: _NoCaptures(),
              permissionGrants: () async =>
                  (overlay: false, backgroundLocation: false, battery: false),
              now: () => now,
            ),
          ),
        ],
        child: MaterialApp(
          theme: SkylineTheme.light(),
          locale: const Locale('hi'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => L10nBinding(child: child!),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// No layout exception, and the screen really is in Hindi.
  void checkHindiFits(WidgetTester tester) {
    check(tester.takeException()).isNull();
    check(L10n.current.localeName).equals('hi');
    final devanagari = RegExp('[ऀ-ॿ]');
    check(
      find
          .byWidgetPredicate(
            (w) => w is Text && devanagari.hasMatch(w.data ?? ''),
          )
          .evaluate(),
    ).isNotEmpty();
  }

  for (final width in const [320.0, 360.0]) {
    group('Hindi at ${width.toInt()} dp wide:', () {
      testWidgets('start, sign-up and update screens on a short phone', (
        tester,
      ) async {
        for (final screen in [
          const StartDrivingScreen(),
          const RegistrationScreen(),
          const UpdateRequiredScreen(
            downloadUrl: 'https://apps.mojud.life/driver',
          ),
        ]) {
          await pumpHindi(tester, screen, width: width, height: 640);
          checkHindiFits(tester);
        }
      });

      testWidgets('the Document View (KYC gate) in every status', (
        tester,
      ) async {
        for (final state in [
          const DriverKyc(),
          _kyc(KycStatus.submitted),
          _kyc(
            KycStatus.rejected,
            reviewNote:
                'The selfie is blurred and the name does not match the '
                'licence. Please take a clear selfie in good light.',
          ),
          _kyc(KycStatus.verified),
          _kyc(KycStatus.unknown),
        ]) {
          kyc.kyc = state;
          await pumpHindi(tester, const DocumentViewScreen(), width: width);
          checkHindiFits(tester);
        }
      });

      testWidgets('each KYC step, empty and filled in', (tester) async {
        for (final state in [const DriverKyc(), _kyc(KycStatus.verified)]) {
          kyc.kyc = state;
          for (final step in const [
            VehicleTypeStep(),
            PhotoAndNameStep(),
            AadharStep(),
            DrivingLicenseStep(),
            PermissionsStep(),
            BankDetailsStep(),
          ]) {
            await pumpHindi(tester, step, width: width);
            checkHindiFits(tester);
          }
        }
      });

      testWidgets('Home on duty, with ride requests', (tester) async {
        kyc.kyc = _kyc(KycStatus.verified);
        await pumpHindi(
          tester,
          const DriverHomeShell(driver: _driver),
          width: width,
        );
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        check(find.byType(RideCard).evaluate()).isNotEmpty();
        checkHindiFits(tester);
      });

      testWidgets('each Rides tab', (tester) async {
        await pumpHindi(tester, const RidesPanel(), width: width);
        checkHindiFits(tester);
        for (final tab in find.byType(Tab).evaluate().toList()) {
          await tester.tap(find.byWidget(tab.widget));
          await tester.pumpAndSettle();
          checkHindiFits(tester);
        }
      });

      testWidgets('a ride\'s screen at each stage', (tester) async {
        for (final r in [
          _multiStop(status: 'requested', withCustomer: false),
          ride(id: 'o2', approximate: true),
          _multiStop(),
          ride(
            id: 'a2',
            status: 'arrived',
            noShowAt: '2026-10-26T07:15:00+05:30',
          ),
          ride(
            id: 'p1',
            status: 'in_progress',
            startedAt: '2026-10-26T02:00:00+05:30',
          ),
          ...rides.mine.skip(2),
        ]) {
          await pumpHindi(tester, RideDetailScreen(ride: r), width: width);
          checkHindiFits(tester);
        }
      });

      testWidgets('Earnings with large amounts and a payout', (tester) async {
        await pumpHindi(tester, const EarningsPanel(), width: width);
        checkHindiFits(tester);
      });

      testWidgets('Account, with the language switch', (tester) async {
        kyc.kyc = _kyc(KycStatus.verified);
        await pumpHindi(
          tester,
          const AccountPanel(driver: _driver),
          width: width,
        );
        checkHindiFits(tester);
        check(find.text('भाषा · Language').evaluate()).isNotEmpty();
      });
    });
  }
}
