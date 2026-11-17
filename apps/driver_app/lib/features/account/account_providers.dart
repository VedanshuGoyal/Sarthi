import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/driver_auth_controller.dart';
import '../auth/driver_auth_providers.dart';
import '../documents/data/document_file_store.dart';
import '../notifications/notification_providers.dart';
import '../rides/rides_providers.dart';
import 'view_model/account_deletion_view_model.dart';

/// The KYC photos still waiting on this phone, cleared after a deletion.
/// Overridden in tests (it touches the disk).
final kycCaptureStoreProvider = Provider<DocumentFileStore>((ref) {
  return DocumentFileStore();
});

/// "Delete account" on the Account tab and the Document View.
///
/// Once the server has erased the account, this phone is tidied up like a
/// log out — off duty, ride pushes stopped, KYC photos still waiting on the
/// device deleted — and then signed out. There's no server log out: every
/// session went with the account. (The off-duty and push calls meet a 401
/// now, which signs the app out a moment early; that's harmless.)
final accountDeletionViewModelProvider =
    ChangeNotifierProvider.autoDispose<AccountDeletionViewModel>((ref) {
      return AccountDeletionViewModel(
        repository: ref.watch(driverAuthRepositoryProvider),
        onDeleted: () async {
          // Read everything before the first await: signing out swaps the
          // Account tab (and so this provider) away.
          final duty = ref.read(dutyViewModelProvider);
          final push = ref.read(pushRegistrationProvider);
          final auth = ref.read(driverAuthControllerProvider.notifier);
          final captures = ref.read(kycCaptureStoreProvider);
          // Each step is best-effort: nothing may stop the sign-out.
          await _quietly(() => duty.setOnline(false));
          await _quietly(
            () => push.stop().timeout(
              const Duration(seconds: 5),
              onTimeout: () {},
            ),
          );
          await _quietly(captures.discardAll);
          await auth.signOut();
        },
      );
    });

Future<void> _quietly(Future<void> Function() step) async {
  try {
    await step();
  } catch (_) {
    // Tidying up; the account is already gone server-side.
  }
}
