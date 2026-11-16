import 'dart:async';

import 'package:checks/checks.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/auth/data/auth_repository.dart';
import 'package:user_app/features/auth/view_model/registration_view_model.dart';

import '../support/fake_backend.dart';

RegistrationViewModel _makeVm({Set<String> registeredPhones = const {}}) =>
    RegistrationViewModel(
      // A mocked backend keeps the tests fast, offline, and deterministic.
      repository: AuthRepository(
        client: fakeBackendClient(registeredPhones: registeredPhones),
      ),
    );

void main() {
  group('RegistrationViewModel', () {
    test('walks phone → otp → profile → done on the happy path', () async {
      final vm = _makeVm();
      check(vm.step).equals(RegistrationStep.phone);

      vm.onPhoneChanged('9876543210');
      await vm.submitPhone();
      check(vm.step).equals(RegistrationStep.otp);
      check(vm.phoneE164).equals('+919876543210');
      check(vm.errorText).isNull();

      await vm.submitOtp(AuthRepository.devOtp);
      check(vm.step).equals(RegistrationStep.profile);

      vm.onDateOfBirthChanged(DateTime(2000, 1, 1));
      await vm.submitProfile(name: 'Asha Sharma', email: 'asha@example.com');
      check(vm.step).equals(RegistrationStep.done);
      check(vm.user).isNotNull();
      check(vm.user!.phoneE164).equals('+919876543210');
      check(vm.user!.name).equals('Asha Sharma');
      check(vm.user!.dateOfBirth).equals(DateTime(2000, 1, 1));
    });

    test(
      'an already-registered number logs in and skips the profile step',
      () async {
        final vm = _makeVm(registeredPhones: {'+919876543210'});
        vm.onPhoneChanged('9876543210');
        await vm.submitPhone();
        check(vm.step).equals(RegistrationStep.otp);

        // Correct OTP on a known number → straight to done, logged in.
        await vm.submitOtp(AuthRepository.devOtp);
        check(vm.step).equals(RegistrationStep.done);
        check(vm.user).isNotNull();
        check(vm.token).equals('tok-existing');
        check(vm.errorText).isNull();
      },
    );

    test('a new number issues a token after registering', () async {
      final vm = _makeVm();
      vm.onPhoneChanged('9876543210');
      await vm.submitPhone();
      await vm.submitOtp(AuthRepository.devOtp);
      check(vm.step).equals(RegistrationStep.profile);

      vm.onDateOfBirthChanged(DateTime(2000, 1, 1));
      await vm.submitProfile(name: 'Asha Sharma', email: 'asha@example.com');
      check(vm.step).equals(RegistrationStep.done);
      check(vm.token).equals('tok-new');
    });

    test('rejects registration when under 18 / no date of birth', () async {
      final vm = _makeVm();
      vm.onPhoneChanged('9876543210');
      await vm.submitPhone();
      await vm.submitOtp(AuthRepository.devOtp);

      // No DOB selected.
      await vm.submitProfile(name: 'Asha Sharma', email: 'asha@example.com');
      check(vm.step).equals(RegistrationStep.profile);
      check(vm.errorText).isNotNull();
    });

    test('rejects an invalid phone without advancing', () async {
      final vm = _makeVm();
      vm.onPhoneChanged('123');
      await vm.submitPhone();
      check(vm.step).equals(RegistrationStep.phone);
      check(vm.errorText).isNotNull();
    });

    test('rejects a wrong OTP and stays on the otp step', () async {
      final vm = _makeVm();
      vm.onPhoneChanged('9876543210');
      await vm.submitPhone();

      await vm.submitOtp('000000');
      check(vm.step).equals(RegistrationStep.otp);
      check(vm.errorText).isNotNull();
    });

    test('back() returns from otp to phone', () async {
      final vm = _makeVm();
      vm.onPhoneChanged('9876543210');
      await vm.submitPhone();
      check(vm.step).equals(RegistrationStep.otp);

      vm.back();
      check(vm.step).equals(RegistrationStep.phone);
    });

    test('starts a one-minute resend cooldown on entering the otp step', () {
      fakeAsync((async) {
        final vm = _makeVm();
        vm.onPhoneChanged('9876543210');
        vm.submitPhone();
        async.flushMicrotasks();

        check(vm.step).equals(RegistrationStep.otp);
        check(vm.canResend).isFalse();
        check(vm.resendCountdown).equals(60);

        async.elapse(const Duration(seconds: 30));
        check(vm.resendCountdown).equals(30);
        check(vm.canResend).isFalse();

        // Once the full minute elapses, resending is allowed again.
        async.elapse(const Duration(seconds: 30));
        check(vm.resendCountdown).equals(0);
        check(vm.canResend).isTrue();

        vm.dispose();
      });
    });

    test('resendOtp is ignored mid-cooldown and restarts it once elapsed', () {
      fakeAsync((async) {
        final vm = _makeVm();
        vm.onPhoneChanged('9876543210');
        vm.submitPhone();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 40));
        check(vm.resendCountdown).equals(20);

        // Tapping resend while still counting down does nothing.
        vm.resendOtp();
        async.flushMicrotasks();
        check(vm.resendCountdown).equals(20);

        // After it elapses a genuine resend restarts the full minute.
        async.elapse(const Duration(seconds: 20));
        check(vm.canResend).isTrue();
        vm.resendOtp();
        async.flushMicrotasks();
        check(vm.resendCountdown).equals(60);
        check(vm.canResend).isFalse();

        vm.dispose();
      });
    });

    test('back() from otp cancels the resend cooldown', () {
      fakeAsync((async) {
        final vm = _makeVm();
        vm.onPhoneChanged('9876543210');
        vm.submitPhone();
        async.flushMicrotasks();
        check(vm.canResend).isFalse();

        vm.back();
        check(vm.step).equals(RegistrationStep.phone);
        check(vm.canResend).isTrue();
        check(vm.resendCountdown).equals(0);

        vm.dispose();
      });
    });

    test('locks resends for 30 minutes after the third attempt', () {
      fakeAsync((async) {
        final vm = _makeVm();
        vm.onPhoneChanged('9876543210');
        vm.submitPhone();
        async.flushMicrotasks();

        // Three resends, each after its one-minute cooldown elapses.
        for (var i = 0; i < RegistrationViewModel.maxResendAttempts; i++) {
          async.elapse(const Duration(minutes: 1));
          check(vm.canResend).isTrue();
          vm.resendOtp();
          async.flushMicrotasks();
        }

        // The cap is now hit: locked out for the full lockout window.
        check(vm.isResendLocked).isTrue();
        check(vm.canResend).isFalse();
        check(vm.resendCountdown).equals(30 * 60);

        // Waiting out the lockout restores the ability to resend.
        async.elapse(const Duration(minutes: 30));
        check(vm.isResendLocked).isFalse();
        check(vm.canResend).isTrue();

        vm.dispose();
      });
    });

    test(
      'invalidates the OTP after five wrong codes and forces a restart',
      () async {
        final vm = _makeVm();
        vm.onPhoneChanged('9876543210');
        await vm.submitPhone();

        for (var i = 0; i < RegistrationViewModel.maxOtpAttempts; i++) {
          check(vm.isOtpInvalidated).isFalse();
          await vm.submitOtp('000000');
        }

        check(vm.isOtpInvalidated).isTrue();
        check(vm.canResend).isFalse();
        check(vm.otpAttemptsRemaining).equals(0);

        // Further submissions are ignored while the code is dead.
        await vm.submitOtp('000000');
        check(vm.step).equals(RegistrationStep.otp);

        // Restarting the flow clears the invalidation.
        vm.back();
        check(vm.step).equals(RegistrationStep.phone);
        check(vm.isOtpInvalidated).isFalse();
        check(
          vm.otpAttemptsRemaining,
        ).equals(RegistrationViewModel.maxOtpAttempts);

        vm.dispose();
      },
    );

    test('a second verify while one is in flight is ignored', () async {
      // The keyboard's "done" key stays live under the disabled button.
      final gate = Completer<void>();
      var verifies = 0;
      final backend = fakeBackendClient(registeredPhones: {'+919876543210'});
      final vm = RegistrationViewModel(
        repository: AuthRepository(
          client: MockClient((request) async {
            if (request.url.path == '/auth/otp/verify') {
              verifies++;
              await gate.future;
            }
            final copy = http.Request(request.method, request.url)
              ..headers.addAll(request.headers)
              ..body = request.body;
            return http.Response.fromStream(await backend.send(copy));
          }),
        ),
      );
      vm.onPhoneChanged('9876543210');
      await vm.submitPhone();

      final first = vm.submitOtp(AuthRepository.devOtp);
      final second = vm.submitOtp(AuthRepository.devOtp);
      gate.complete();
      await Future.wait([first, second]);

      check(verifies).equals(1);
      check(vm.step).equals(RegistrationStep.done);
      check(vm.errorText).isNull();
      vm.dispose();
    });

    test(
      'signing in disposes the flow mid-request without a notify after',
      () async {
        // Signing in swaps the registration screen out, which disposes this
        // autoDispose view model before the request's own tail runs.
        late final RegistrationViewModel vm;
        vm = RegistrationViewModel(
          repository: AuthRepository(
            client: fakeBackendClient(registeredPhones: {'+919876543210'}),
          ),
          onSignedIn: (_) async => vm.dispose(),
        );
        vm.onPhoneChanged('9876543210');
        await vm.submitPhone();

        await vm.submitOtp(AuthRepository.devOtp);
        check(vm.step).equals(RegistrationStep.done);
      },
    );
  });
}
