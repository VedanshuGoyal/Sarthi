import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/driver_auth_controller.dart';
import 'data/driver_kyc_repository.dart';
import 'view_model/document_registration_view_model.dart';

/// Single shared [DriverKycRepository].
///
/// Its bearer token is read synchronously, on demand, from the in-memory
/// [driverAuthControllerProvider], so every request uses the current token
/// without the repository holding its own copy — same arrangement as
/// `driverAuthRepositoryProvider`.
final driverKycRepositoryProvider = Provider<DriverKycRepository>((ref) {
  return DriverKycRepository(
    tokenGetter: () =>
        ref.read(driverAuthControllerProvider).valueOrNull?.token,
  );
});

/// The Document View flow's view model.
///
/// Not `autoDispose`: the driver navigates in and out of six sub-screens via
/// `Navigator.push`/`pop`, and the loaded state must survive each of those —
/// only a fresh sign-in (a new provider container) should reset it.
final documentRegistrationViewModelProvider =
    ChangeNotifierProvider<DocumentRegistrationViewModel>((ref) {
      return DocumentRegistrationViewModel(
        repository: ref.watch(driverKycRepositoryProvider),
      );
    });
