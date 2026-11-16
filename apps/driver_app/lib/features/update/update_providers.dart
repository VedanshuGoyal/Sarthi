import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_build.dart';
import '../../core/services/app_http_client.dart';
import '../auth/driver_auth_controller.dart';
import 'data/app_config_repository.dart';
import 'view_model/update_gate_view_model.dart';

/// `GET /app/config`. Its own client — time-limited and carrying the build
/// headers like [backendClientProvider], without that client's hooks: the
/// route is never refused, and the backend client's 426 hook reads the gate
/// below, so the gate must not depend on it.
final appConfigRepositoryProvider = Provider<AppConfigRepository>((ref) {
  return AppConfigRepository(
    client: AppHttpClient(
      inner: ref.watch(httpClientProvider),
      headers: AppBuild.headers,
    ),
  );
});

/// The app-wide update gate: closed by a 426 from any backend call (see
/// [backendClientProvider]) or by `/app/config` at startup.
final updateGateProvider = ChangeNotifierProvider<UpdateGateViewModel>((ref) {
  return UpdateGateViewModel(
    repository: ref.watch(appConfigRepositoryProvider),
  );
});
