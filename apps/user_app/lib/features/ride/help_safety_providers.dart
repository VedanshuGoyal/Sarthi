import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config_repository.dart';
import '../auth/auth_controller.dart';

/// The server's app-wide settings (`GET /app/config`, no session needed).
final appConfigRepositoryProvider = Provider<AppConfigRepository>((ref) {
  return AppConfigRepository(client: ref.watch(backendClientProvider));
});

/// The number "Contact support" opens a WhatsApp chat with, or null to hide
/// the button. Fetched once per app session; never fails.
final supportPhoneProvider = FutureProvider<String?>((ref) {
  return ref.watch(appConfigRepositoryProvider).supportPhone();
});
