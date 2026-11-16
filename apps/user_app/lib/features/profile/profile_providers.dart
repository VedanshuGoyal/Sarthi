import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_providers.dart';
import '../notifications/notification_providers.dart';
import '../ride/data/recent_locations_storage.dart';
import '../ride/data/saved_cars_storage.dart';
import 'view_model/account_deletion_view_model.dart';

/// "Delete account" on the profile page. Once the server has erased the
/// account this phone forgets it too: the per-account copies of the
/// customer's pickups and cars are emptied, notifications are withdrawn and
/// the session is cleared — back to onboarding. (No server logout: erasing
/// the account already revoked every session.)
final accountDeletionViewModelProvider =
    ChangeNotifierProvider.autoDispose<AccountDeletionViewModel>((ref) {
      return AccountDeletionViewModel(
        repository: ref.watch(authRepositoryProvider),
        onDeleted: () async {
          // Read everything first: signing out disposes this provider.
          final auth = ref.read(authControllerProvider.notifier);
          final push = ref.read(pushRegistrationProvider);
          final userId = auth.session?.user.id;
          if (userId != null) {
            await _forgetOnThisPhone(userId);
          }
          try {
            await push.stop().timeout(
              const Duration(seconds: 5),
              onTimeout: () {},
            );
          } catch (e) {
            debugPrint('push: unregistering after deletion failed: $e');
          }
          await auth.signOut();
        },
      );
    });

/// Empties the account's on-device caches (best-effort).
Future<void> _forgetOnThisPhone(String userId) async {
  try {
    await Future.wait([
      SecureRecentLocationsStorage(userId: userId).write(const []),
      SecureSavedCarsStorage(userId: userId).write(const []),
    ]);
  } catch (e) {
    debugPrint('account deleted; clearing local caches failed: $e');
  }
}
