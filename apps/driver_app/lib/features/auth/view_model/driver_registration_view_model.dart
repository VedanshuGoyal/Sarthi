import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/driver_auth_repository.dart';
import '../domain/auth_validators.dart';
import '../domain/driver.dart';
import '../domain/driver_auth_session.dart';

/// The steps a new driver moves through, in order.
enum DriverRegistrationStep { phone, otp, name, done }

/// Drives the phone → OTP → name registration flow for the driver app.
///
/// A [ChangeNotifier] (per the MVVM guideline): it owns all transient state for
/// the flow — the current [step], the [isLoading] flag, field-level
/// [errorText], and the typed values — and exposes command methods the views
/// call. It transforms repository results for the UI and never touches
/// widgets, the network, or storage directly. Mirrors the customer app's
/// `RegistrationViewModel`, minus the profile step's email/date-of-birth —
/// drivers chauffeur the customer's own car, so a name is all registration
/// needs; vehicle details come later, outside this flow.
class DriverRegistrationViewModel extends ChangeNotifier {
  /// [initialStep] and [phoneNational] are seams used by previews and tests to
  /// start the flow partway through; production code uses the defaults.
  DriverRegistrationViewModel({
    required this._repository,
    this._onSignedIn,
    DriverRegistrationStep initialStep = DriverRegistrationStep.phone,
    this._phoneNational = '',
  }) : _step = initialStep {
    // When a flow starts already on the OTP step (previews/tests), a code has
    // implicitly just been sent, so begin the resend cooldown too.
    if (_step == DriverRegistrationStep.otp) _startCountdown(resendCooldown);
  }

  final DriverAuthRepository _repository;

  /// How long the driver must wait between OTP sends before "Resend" re-enables.
  static const Duration resendCooldown = Duration(minutes: 1);

  /// How many times a code may be resent within one OTP session before the
  /// number is locked out. Mirrors the backend's cap for immediate UX.
  static const int maxResendAttempts = 3;

  /// How long resends stay locked once [maxResendAttempts] is reached. The
  /// driver waits it out or restarts the flow with a fresh number.
  static const Duration resendLockout = Duration(minutes: 30);

  /// How many wrong codes are tolerated before the OTP is invalidated and the
  /// driver must request a new one. Mirrors the backend's cap.
  static const int maxOtpAttempts = 5;

  /// Called once a session is obtained (login or registration) so app-wide
  /// state (`DriverAuthController`) can store it in memory + secure storage.
  final Future<void> Function(DriverAuthSession session)? _onSignedIn;

  DriverRegistrationStep _step;
  DriverRegistrationStep get step => _step;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Field-level validation/server error for the *current* step, or null.
  String? _errorText;
  String? get errorText => _errorText;

  String _phoneNational;
  String get phoneNational => _phoneNational;

  /// Full E.164 number, e.g. `+919876543210`.
  String get phoneE164 => '+91$_phoneNational';

  Driver? _driver;
  Driver? get driver => _driver;

  /// The session token issued on login/registration, or null before auth.
  /// Sent as a bearer token on authenticated requests.
  String? _token;
  String? get token => _token;

  /// Number of digits the OTP screen should collect.
  int get otpLength => DriverAuthRepository.otpLength;

  Timer? _resendTimer;

  /// Seconds left before the OTP can be resent (or before a lockout clears);
  /// 0 once the wait is over.
  int _resendCountdown = 0;
  int get resendCountdown => _resendCountdown;

  /// Resend-endpoint uses so far this session, capped at [maxResendAttempts].
  int _resendCount = 0;

  /// True once the resend cap is hit: resends are locked for [resendLockout].
  bool _resendLocked = false;
  bool get isResendLocked => _resendLocked;

  /// Wrong-code verifications so far this session.
  int _otpAttempts = 0;

  /// True once the OTP has been invalidated (too many wrong codes). The
  /// driver must restart the flow to get a fresh code.
  bool _otpInvalidated = false;
  bool get isOtpInvalidated => _otpInvalidated;

  /// Whether the resend button should be enabled: not mid-cooldown, not locked
  /// out, and the OTP still valid.
  bool get canResend =>
      _resendCountdown == 0 && !_resendLocked && !_otpInvalidated;

  // --- Step 1: phone ---------------------------------------------------------

  void onPhoneChanged(String value) {
    _phoneNational = value;
    if (_errorText != null) {
      _errorText = null;
      notifyListeners();
    }
  }

  /// Validates the number and, if valid, requests an OTP and advances to the
  /// OTP step.
  Future<void> submitPhone() async {
    final error = AuthValidators.phoneNational(_phoneNational);
    if (error != null) return _fail(error);

    await _run(() async {
      await _repository.requestOtp(phoneE164);
      _step = DriverRegistrationStep.otp;
      _resetOtpSession();
      _startCountdown(resendCooldown);
    });
  }

  // --- Step 2: OTP -----------------------------------------------------------

  void onOtpChanged(String _) {
    if (_errorText != null) {
      _errorText = null;
      notifyListeners();
    }
  }

  /// Verifies [code]. If the number already has an account, the driver is
  /// logged in and the flow jumps to [DriverRegistrationStep.done]; otherwise
  /// it advances to the name step to finish registration.
  Future<void> submitOtp(String code) async {
    if (_otpInvalidated) return;
    final error = AuthValidators.otp(code, length: otpLength);
    if (error != null) return _fail(error);

    await _run(() async {
      try {
        final result = await _repository.verifyOtp(
          phoneE164: phoneE164,
          code: code,
        );
        if (result.registered) {
          // Returning driver — log in and go straight to home.
          await _completeSignIn(result.session!);
        } else {
          _step = DriverRegistrationStep.name;
        }
      } on OtpInvalidatedException {
        // Backend already killed the code (e.g. our count drifted).
        _invalidateOtp();
        rethrow;
      } on OtpIncorrectException {
        // A genuine wrong code: count it toward the invalidation cap.
        _otpAttempts++;
        if (_otpAttempts >= maxOtpAttempts) _invalidateOtp();
        rethrow;
      }
    });
  }

  /// Re-sends the OTP for the same number via the dedicated resend endpoint.
  ///
  /// A no-op unless [canResend] (mid-cooldown, locked out, or invalidated), so
  /// callers can't spam the endpoint. On the [maxResendAttempts]-th send the
  /// number is locked out for [resendLockout]; the backend enforces the same.
  Future<void> resendOtp() async {
    if (!canResend) return;
    await _run(() async {
      try {
        await _repository.resendOtp(phoneE164);
      } on OtpResendLockedException catch (e) {
        _enterResendLockout(e.retryAfter);
        rethrow;
      }
      _resendCount++;
      if (_resendCount >= maxResendAttempts) {
        _enterResendLockout(resendLockout);
      } else {
        _startCountdown(resendCooldown);
      }
    });
  }

  /// Clears per-session OTP counters/flags for a freshly issued code.
  void _resetOtpSession() {
    _resendCount = 0;
    _otpAttempts = 0;
    _resendLocked = false;
    _otpInvalidated = false;
  }

  /// Locks resends for [wait] (cap reached), surfacing a live countdown.
  void _enterResendLockout(Duration wait) {
    _resendLocked = true;
    _resendCount = maxResendAttempts;
    _startCountdown(wait);
  }

  /// Marks the OTP dead: stops the countdown; the view offers a restart.
  void _invalidateOtp() {
    _otpInvalidated = true;
    _resendTimer?.cancel();
    _resendCountdown = 0;
  }

  /// (Re)starts a countdown of [duration], ticking [resendCountdown] down to
  /// zero and notifying listeners each second. When a lockout countdown ends,
  /// the resend allowance is restored (matching the backend).
  void _startCountdown(Duration duration) {
    _resendTimer?.cancel();
    _resendCountdown = duration.inSeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _resendCountdown--;
      if (_resendCountdown <= 0) {
        _resendCountdown = 0;
        timer.cancel();
        if (_resendLocked) {
          // Lockout served — waiting it out restores the resend allowance.
          _resendLocked = false;
          _resendCount = 0;
        }
      }
      notifyListeners();
    });
  }

  // --- Step 3: name ------------------------------------------------------

  /// Validates the name, registers the account, and finishes the flow.
  Future<void> submitName(String name) async {
    final error = AuthValidators.name(name);
    if (error != null) return _fail(error);

    await _run(() async {
      final session = await _repository.register(
        phoneE164: phoneE164,
        name: name,
      );
      await _completeSignIn(session);
    });
  }

  /// Records a session on the flow and hands it to app-wide state for
  /// persistence, then finishes the flow.
  Future<void> _completeSignIn(DriverAuthSession session) async {
    _driver = session.driver;
    _token = session.token;
    _step = DriverRegistrationStep.done;
    await _onSignedIn?.call(session);
  }

  // --- Navigation ------------------------------------------------------------

  /// Goes back one step (e.g. to correct the phone number), clearing errors.
  void back() {
    _errorText = null;
    switch (_step) {
      case DriverRegistrationStep.otp:
        _resendTimer?.cancel();
        _resendCountdown = 0;
        _resetOtpSession();
        _step = DriverRegistrationStep.phone;
      case DriverRegistrationStep.name:
        _step = DriverRegistrationStep.otp;
      case DriverRegistrationStep.phone:
      case DriverRegistrationStep.done:
        break;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  // --- Internals -------------------------------------------------------------

  /// Runs [action] with the loading flag set, mapping [AuthException]s to
  /// [errorText] and unexpected errors to a generic message.
  Future<void> _run(Future<void> Function() action) async {
    _isLoading = true;
    _errorText = null;
    notifyListeners();
    try {
      await action();
    } on AuthException catch (e) {
      _errorText = e.message;
    } catch (_) {
      _errorText = 'Something went wrong. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _fail(String message) {
    _errorText = message;
    notifyListeners();
  }
}
