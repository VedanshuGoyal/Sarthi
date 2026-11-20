// The sign-in steps, the update screen, the Account tab and the add-car
// sheet in Hindi on 320 and 360 dp wide phones: no overflow, and in Hindi.

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/auth/auth_controller.dart';
import 'package:user_app/features/auth/auth_providers.dart';
import 'package:user_app/features/auth/data/auth_repository.dart';
import 'package:user_app/features/auth/data/session_storage.dart';
import 'package:user_app/features/auth/domain/auth_session.dart';
import 'package:user_app/features/auth/domain/auth_user.dart';
import 'package:user_app/features/auth/view/registration_screen.dart';
import 'package:user_app/features/auth/view_model/registration_view_model.dart';
import 'package:user_app/features/language/data/language_repository.dart';
import 'package:user_app/features/language/domain/app_language.dart';
import 'package:user_app/features/language/language_providers.dart';
import 'package:user_app/features/profile/view/profile_screen.dart';
import 'package:user_app/features/ride/data/cars_repository.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/widgets/add_car_sheet.dart';
import 'package:user_app/features/ride/view_model/saved_cars_view_model.dart';
import 'package:user_app/features/update/view/update_required_screen.dart';
import 'package:user_app/l10n/l10n.dart';

import '../support/fake_backend.dart';
import '../support/hindi.dart';

final _user = AuthUser(
  id: 'u1',
  phoneE164: '+919876543210',
  name: 'Rameshwar Prasad Chaurasia Bhardwaj',
  email: 'rameshwar.prasad.chaurasia@example.co.in',
  dateOfBirth: DateTime(1988, 9, 28),
);

const _cars = [
  Car(
    id: 'c1',
    registration: 'HR26DK8337',
    type: CarType.luxury,
    transmission: Transmission.automatic,
  ),
  Car(
    id: 'c2',
    registration: 'DL01AB1234',
    type: CarType.hatchback,
    transmission: Transmission.manual,
  ),
];

/// Saved cars in memory; nothing on the network or the phone.
class _Cars extends CarsRepository {
  @override
  Future<List<Car>> list() async => _cars;
}

/// The phone follows its own language: the switch says so.
class _Languages implements LanguageRepository {
  @override
  Future<AppLanguage> read() async => AppLanguage.system;
  @override
  Future<void> write(AppLanguage language) async {}
}

class _Session implements SessionStorage {
  @override
  Future<AuthSession?> read() async => AuthSession(token: 'tok-1', user: _user);
  @override
  Future<void> write(AuthSession session) async {}
  @override
  Future<void> clear() async {}
}

/// The sign-in flow, started at [step] for a number already typed in.
RegistrationViewModel _flowAt(RegistrationStep step) => RegistrationViewModel(
  repository: AuthRepository(client: fakeBackendClient()),
  initialStep: step,
  phoneNational: '9876543210',
);

void main() {
  tearDown(L10n.reset);

  final overrides = <Override>[
    languageRepositoryProvider.overrideWithValue(_Languages()),
    sessionStorageProvider.overrideWithValue(_Session()),
    savedCarsViewModelProvider.overrideWith(
      (ref) => SavedCarsViewModel(repository: _Cars(), initialCars: _cars),
    ),
  ];

  /// Drops the last screen and its providers, so the next one starts fresh.
  Future<void> clear(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  for (final width in hindiWidths) {
    group('Hindi at ${width.toInt()} dp wide:', () {
      testWidgets('the phone step, on a short and a tall phone', (
        tester,
      ) async {
        for (final height in const [640.0, 800.0]) {
          await pumpHindi(
            tester,
            const RegistrationScreen(),
            width: width,
            height: height,
            overrides: overrides,
          );
          checkHindiFits(tester);
          check(find.text('अपना मोबाइल नंबर डालें').evaluate()).isNotEmpty();

          // A wrong number: the field's error, in Hindi.
          await tester.enterText(find.byType(TextField), '12345');
          await tester.tap(
            find.widgetWithText(SarthiPrimaryButton, 'आगे बढ़ें'),
          );
          await tester.pumpAndSettle();
          checkHindiFits(tester);
          check(
            find.text('सही 10 अंकों का मोबाइल नंबर डालें').evaluate(),
          ).isNotEmpty();
          await clear(tester);
        }
      });

      testWidgets('the OTP step, counting down, then locked out', (
        tester,
      ) async {
        final flow = _flowAt(RegistrationStep.otp);
        await pumpHindi(
          tester,
          const RegistrationScreen(),
          width: width,
          height: 640,
          overrides: [
            ...overrides,
            registrationViewModelProvider.overrideWith((ref) => flow),
          ],
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 400));
        checkHindiFits(tester);
        check(
          find.textContaining('बाद OTP दोबारा भेजें').evaluate(),
        ).isNotEmpty();

        // A wrong-length code.
        await tester.enterText(find.byType(TextField), '12');
        await tester.tap(
          find.widgetWithText(SarthiPrimaryButton, 'वेरिफ़ाई करें'),
        );
        await tester.pump();
        checkHindiFits(tester);
        check(find.text('6 अंकों का OTP डालें').evaluate()).isNotEmpty();

        // Resent until the cap: locked out, with a countdown.
        for (var i = 0; i < RegistrationViewModel.maxResendAttempts; i++) {
          await tester.pump(RegistrationViewModel.resendCooldown);
          await tester.tap(find.text('OTP दोबारा भेजें'));
          await tester.pump();
          await tester.pump();
        }
        checkHindiFits(tester);
        check(
          find.textContaining('बहुत बार OTP माँगा गया').evaluate(),
        ).isNotEmpty();
        await clear(tester);
      });

      testWidgets('the OTP step after too many wrong codes', (tester) async {
        final flow = _flowAt(RegistrationStep.otp);
        await pumpHindi(
          tester,
          const RegistrationScreen(),
          width: width,
          height: 640,
          overrides: [
            ...overrides,
            registrationViewModelProvider.overrideWith((ref) => flow),
          ],
          settle: false,
        );
        for (var i = 0; i < RegistrationViewModel.maxOtpAttempts; i++) {
          await tester.runAsync(() => flow.submitOtp('000000'));
        }
        await tester.pump();
        checkHindiFits(tester);
        check(
          find.textContaining('यह OTP अब काम नहीं करेगा').evaluate(),
        ).isNotEmpty();
        check(find.text('फिर से शुरू करें').evaluate()).isNotEmpty();
        await clear(tester);
      });

      testWidgets('the profile step, with its errors and the consent line', (
        tester,
      ) async {
        await pumpHindi(
          tester,
          const RegistrationScreen(),
          width: width,
          height: 900,
          overrides: [
            ...overrides,
            registrationViewModelProvider.overrideWith(
              (ref) => _flowAt(RegistrationStep.profile),
            ),
          ],
        );
        checkHindiFits(tester);
        check(find.textContaining('सहमत हूँ').evaluate()).isNotEmpty();

        // Nothing filled in: the name's error shows under the name.
        await tester.tap(
          find.widgetWithText(SarthiPrimaryButton, 'अकाउंट बनाएँ'),
        );
        await tester.pump();
        checkHindiFits(tester);
        check(find.text('अपना नाम डालें').evaluate()).isNotEmpty();

        // Everything but the consent: its error, under the checkbox.
        await tester.enterText(find.byType(TextField).at(0), 'Asha Sharma');
        await tester.enterText(
          find.byType(TextField).at(1),
          'asha@example.com',
        );
        final vm = ProviderScope.containerOf(
          tester.element(find.byType(RegistrationScreen)),
        ).read(registrationViewModelProvider);
        vm.onDateOfBirthChanged(DateTime(2000, 1, 12));
        await tester.tap(
          find.widgetWithText(SarthiPrimaryButton, 'अकाउंट बनाएँ'),
        );
        await tester.pump();
        checkHindiFits(tester);
        check(find.text('12 जनवरी 2000').evaluate()).isNotEmpty();
        check(
          find.text(L10n.current.authConsentRequired).evaluate(),
        ).isNotEmpty();
        await clear(tester);
      });

      testWidgets('the update-required screen, before and after a failed '
          'open', (tester) async {
        await pumpHindi(
          tester,
          UpdateRequiredScreen(
            downloadUrl: 'https://apps.mojud.life/user',
            openUrl: (_) async => false,
          ),
          width: width,
          height: 640,
          overrides: overrides,
        );
        checkHindiFits(tester);

        await tester.tap(find.text('नया वर्ज़न डाउनलोड करें'));
        await tester.pumpAndSettle();
        checkHindiFits(tester);
        check(
          find.textContaining('ब्राउज़र नहीं खुला').evaluate(),
        ).isNotEmpty();
      });

      testWidgets('the Account tab: long name, saved cars, language, delete', (
        tester,
      ) async {
        await pumpHindi(
          tester,
          ProfileScreen(user: _user, onLogout: () {}),
          width: width,
          overrides: overrides,
        );
        checkHindiFits(tester);
        check(find.text('भाषा · Language').evaluate()).isNotEmpty();
        check(find.text('लग्ज़री · ऑटोमैटिक').evaluate()).isNotEmpty();
        check(find.text('28 सितंबर 1988').evaluate()).isNotEmpty();
        check(find.text('लॉग आउट').evaluate()).isNotEmpty();

        // The delete confirmation, with its long explanation.
        await tester.ensureVisible(find.text('अकाउंट डिलीट करें'));
        await tester.tap(find.text('अकाउंट डिलीट करें'));
        await tester.pumpAndSettle();
        checkHindiFits(tester);
        check(find.text('अपना अकाउंट डिलीट करें?').evaluate()).isNotEmpty();
      });

      testWidgets('the add-car sheet, with a half-typed number', (
        tester,
      ) async {
        await pumpHindi(
          tester,
          const Scaffold(body: AddCarSheet()),
          width: width,
          height: 640,
          overrides: overrides,
        );
        checkHindiFits(tester);

        await tester.enterText(find.byType(TextField), 'HR2');
        await tester.pump();
        checkHindiFits(tester);
        check(find.text('कार का पूरा नंबर डालें।').evaluate()).isNotEmpty();
      });
    });
  }
}
