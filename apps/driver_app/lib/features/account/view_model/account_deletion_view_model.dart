import 'package:flutter/foundation.dart';

import '../../auth/data/driver_auth_repository.dart';

/// Deleting the driver's account from the Account tab.
///
/// The server does the erasing; on success [_onDeleted] tidies up the
/// phone (off duty, no ride pushes, no leftover KYC photos) and signs out.
/// While the server refuses — a ride is underway, or a customer hasn't paid
/// for one yet — [error] carries its reason and the driver stays signed in.
class AccountDeletionViewModel extends ChangeNotifier {
  AccountDeletionViewModel({
    required this._repository,
    required this._onDeleted,
  });

  final DriverAuthRepository _repository;
  final Future<void> Function() _onDeleted;

  bool _isDeleting = false;
  bool get isDeleting => _isDeleting;

  /// Why the last attempt failed, safe to show; null otherwise.
  String? _error;
  String? get error => _error;

  bool _disposed = false;

  /// Asks the server to delete the account. True once it has (and the
  /// driver has been signed out here); false with [error] set otherwise.
  Future<bool> deleteAccount() async {
    if (_isDeleting) return false;
    _isDeleting = true;
    _error = null;
    _notify();
    try {
      await _repository.deleteAccount();
    } on AuthException catch (e) {
      // AccountBusyException carries the server's reason; a
      // SessionExpiredException means the app is already signing out.
      _error = e.message;
      _isDeleting = false;
      _notify();
      return false;
    } catch (_) {
      _error = "Couldn't delete your account. Please try again.";
      _isDeleting = false;
      _notify();
      return false;
    }
    await _onDeleted();
    _isDeleting = false;
    _notify();
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
