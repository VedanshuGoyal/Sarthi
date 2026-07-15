import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'data/auth_repository.dart';
import 'view_model/registration_view_model.dart';

/// Single shared [AuthRepository] instance.
///
/// Its bearer token is read synchronously, on demand, from the in-memory
/// [authControllerProvider] — so authenticated requests always use the current
/// token without the repository holding its own copy.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    tokenGetter: () => ref.read(authControllerProvider).valueOrNull?.token,
  );
});

/// The registration flow's view model.
///
/// `ChangeNotifierProvider` adapts our MVVM [ChangeNotifier] into Riverpod so
/// views can `watch` it for rebuilds while the repository stays injected via
/// the constructor. `autoDispose` resets the flow when no screen is listening.
/// On success it hands the session to [authControllerProvider], which persists
/// it to memory + secure storage.
final registrationViewModelProvider =
    ChangeNotifierProvider.autoDispose<RegistrationViewModel>((ref) {
      return RegistrationViewModel(
        repository: ref.watch(authRepositoryProvider),
        onSignedIn: (session) =>
            ref.read(authControllerProvider.notifier).signIn(session),
      );
    });
