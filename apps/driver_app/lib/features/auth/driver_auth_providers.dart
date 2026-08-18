import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/driver_auth_repository.dart';
import 'driver_auth_controller.dart';
import 'view_model/driver_registration_view_model.dart';

/// Single shared [DriverAuthRepository] instance.
///
/// Its bearer token is read synchronously, on demand, from the in-memory
/// [driverAuthControllerProvider] — so authenticated requests always use the
/// current token without the repository holding its own copy.
final driverAuthRepositoryProvider = Provider<DriverAuthRepository>((ref) {
  return DriverAuthRepository(
    tokenGetter: () =>
        ref.read(driverAuthControllerProvider).valueOrNull?.token,
  );
});

/// The driver registration flow's view model.
///
/// `ChangeNotifierProvider` adapts our MVVM [ChangeNotifier] into Riverpod so
/// views can `watch` it for rebuilds while the repository stays injected via
/// the constructor. `autoDispose` resets the flow when no screen is listening.
/// On success it hands the session to [driverAuthControllerProvider], which
/// persists it to memory + secure storage.
final driverRegistrationViewModelProvider =
    ChangeNotifierProvider.autoDispose<DriverRegistrationViewModel>((ref) {
      return DriverRegistrationViewModel(
        repository: ref.watch(driverAuthRepositoryProvider),
        onSignedIn: (session) =>
            ref.read(driverAuthControllerProvider.notifier).signIn(session),
      );
    });
