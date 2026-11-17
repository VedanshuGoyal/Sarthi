import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/driver_auth_controller.dart';
import 'app_config_repository.dart';

/// Single shared [AppConfigRepository]; it keeps the backend's config once
/// read, for the rest of the app session.
final appConfigRepositoryProvider = Provider<AppConfigRepository>((ref) {
  return AppConfigRepository(client: ref.watch(backendClientProvider));
});

/// MOJUD support's WhatsApp number, or null to hide "Contact support".
/// `autoDispose`, so a screen opened after a failed read asks again (the
/// repository caches a successful one).
final supportPhoneProvider = FutureProvider.autoDispose<String?>((ref) {
  return ref.watch(appConfigRepositoryProvider).supportPhone();
});
