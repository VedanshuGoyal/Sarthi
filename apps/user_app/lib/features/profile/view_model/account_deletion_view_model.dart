import 'package:flutter/foundation.dart';

import '../../../l10n/l10n.dart';
import '../../auth/data/auth_repository.dart';

/// Deleting the customer's account from the profile page.
///
/// Asks the server to erase the account and, once it has, hands over to
/// [_onDeleted] (sign out on this phone). While the request runs
/// [isDeleting] is true; a refusal or failure leaves the customer signed in
/// with [errorText] saying why.
class AccountDeletionViewModel extends ChangeNotifier {
  AccountDeletionViewModel({
    required this._repository,
    required this._onDeleted,
  });

  final AuthRepository _repository;
  final Future<void> Function() _onDeleted;

  bool _isDeleting = false;
  bool get isDeleting => _isDeleting;

  String? _errorText;
  String? get errorText => _errorText;

  bool _disposed = false;

  /// Erases the account; true once it is gone and the customer signed out.
  /// Ignored while a request is already in flight.
  Future<bool> deleteAccount() async {
    if (_isDeleting) return false;
    _isDeleting = true;
    _errorText = null;
    _notify();
    try {
      await _repository.deleteAccount();
    } on AuthException catch (e) {
      return _fail(e.message);
    } catch (_) {
      return _fail(L10n.current.accountDeleteFailed);
    }
    // The server has erased it and revoked the session; a failure signing
    // out here must not report the deletion as failed.
    try {
      await _onDeleted();
    } catch (e) {
      debugPrint('account deleted; signing out failed: $e');
    }
    _isDeleting = false;
    _notify();
    return true;
  }

  bool _fail(String message) {
    _isDeleting = false;
    _errorText = message;
    _notify();
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
