import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/auth_repository.dart';
import '../domain/auth_session.dart';
import '../domain/auth_user.dart';
import '../domain/auth_validators.dart';

/// The steps a new customer moves through, in order.
enum RegistrationStep { phone, otp, profile, done }

/// Drives the phone → OTP → profile registration flow.
///
/// A [ChangeNotifier] (per the MVVM guideline): it owns all transient state for
/// the flow — the current [step], the [isLoading] flag, field-level
/// [errorText], and the typed values — and exposes command methods the views
/// call. It transforms repository results for the UI and never touches widgets,
/// the network, or storage directly.
class RegistrationViewModel extends ChangeNotifier {
  /// [initialStep] and [phoneNational] are seams used by previews and tests to
  /// start the flow partway through; production code uses the defaults.
  RegistrationViewModel({
    required this._repository,
    this._onSignedIn,
    RegistrationStep initialStep = RegistrationStep.phone,
    this._phoneNational = '',
  }) : _step = initialStep {
    // When a flow starts already on the OTP step (previews/tests), a code has
    // implicitly just been sent, so begin the resend cooldown too.
    if (_step == RegistrationStep.otp) _startCountdown(resendCooldown);
  }

  final AuthRepository _repository;

  /// How long the user must wait between OTP sends before "Resend" re-enables.
  static const Duration resendCooldown = Duration(minutes: 1);

  /// How many times a code may be resent within one OTP session before the
  /// number is locked out. Mirrors the backend's cap for immediate UX.
  static const int maxResendAttempts = 3;

  /// How long resends stay locked once [maxResendAttempts] is reached. The user
  /// waits it out or restarts the flow with a fresh number.
  static const Duration resendLockout = Duration(minutes: 30);

  /// How many wrong codes are tolerated before the OTP is invalidated and the
  /// user must request a new one. Mirrors the backend's cap.
  static const int maxOtpAttempts = 5;

  /// Called once a session is obtained (login or registration) so app-wide
  /// state (`AuthController`) can store it in memory + secure storage.
  final Future<void> Function(AuthSession session)? _onSignedIn;

  RegistrationStep _step;
  RegistrationStep get step => _step;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Field-level validation/server error for the *current* step, or null.
  String? _errorText;
  String? get errorText => _errorText;

  String _phoneNational;
  String get phoneNational => _phoneNational;

  /// Full E.164 number, e.g. `+919876543210`.
  String get phoneE164 => '+91$_phoneNational';

  DateTime? _dateOfBirth;
  DateTime? get dateOfBirth => _dateOfBirth;

  AuthUser? _user;
  AuthUser? get user => _user;

  /// The session token issued on login/registration, or null before auth.
  /// Sent as a bearer token on authenticated requests.
  String? _token;
  String? get token => _token;

  /// Number of digits the OTP screen should collect.
  int get otpLength => AuthRepository.otpLength;

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

  /// Verification attempts remaining before the OTP is invalidated.
  int get otpAttemptsRemaining =>
      (maxOtpAttempts - _otpAttempts).clamp(0, maxOtpAttempts);

  /// True once the OTP has been invalidated (too many wrong codes). The user
  /// must restart the flow to get a fresh code.
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
      _step = RegistrationStep.otp;
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

  /// Verifies [code]. If the number already has an account, the user is logged
  /// in and the flow jumps to [RegistrationStep.done]; otherwise it advances to
  /// the profile step to finish registration.
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
          // Returning customer — log in and go straight to home.
          await _completeSignIn(result.session!);
        } else {
          _step = RegistrationStep.profile;
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

  // --- Step 3: profile -------------------------------------------------------

  /// Records the date picked in the calendar, clearing any prior error.
  void onDateOfBirthChanged(DateTime value) {
    _dateOfBirth = value;
    if (_errorText != null) {
      _errorText = null;
      notifyListeners();
    }
  }

  /// Validates name + email + date of birth, registers the account, and
  /// finishes the flow.
  Future<void> submitProfile({
    required String name,
    required String email,
  }) async {
    final error =
        AuthValidators.name(name) ??
        AuthValidators.email(email) ??
        AuthValidators.dateOfBirth(_dateOfBirth);
    if (error != null) return _fail(error);

    await _run(() async {
      final session = await _repository.register(
        phoneE164: phoneE164,
        name: name,
        email: email,
        dateOfBirth: _dateOfBirth!,
      );
      await _completeSignIn(session);
    });
  }

  /// Records a session on the flow and hands it to app-wide state for
  /// persistence, then finishes the flow.
  Future<void> _completeSignIn(AuthSession session) async {
    _user = session.user;
    _token = session.token;
    _step = RegistrationStep.done;
    await _onSignedIn?.call(session);
  }

  // --- Navigation ------------------------------------------------------------

  /// Goes back one step (e.g. to correct the phone number), clearing errors.
  void back() {
    _errorText = null;
    switch (_step) {
      case RegistrationStep.otp:
        _resendTimer?.cancel();
        _resendCountdown = 0;
        _resetOtpSession();
        _step = RegistrationStep.phone;
      case RegistrationStep.profile:
        _step = RegistrationStep.otp;
      case RegistrationStep.phone:
      case RegistrationStep.done:
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
