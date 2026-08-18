import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/driver_session_storage.dart';
import 'domain/driver_auth_session.dart';

/// The durable session store (secure storage). Overridden in tests with a fake.
final driverSessionStorageProvider = Provider<DriverSessionStorage>((ref) {
  return SecureDriverSessionStorage();
});

/// App-wide authentication state and the single source of truth for the
/// current driver session.
///
/// It keeps the session in memory for instant, synchronous reads while
/// mirroring every change to secure storage:
///
///  * **On launch** — [build] reads the persisted session asynchronously and
///    loads it into memory (the returned [AsyncValue] is `loading` until then).
///  * **At runtime** — [token] / [session] read straight from memory, no await.
///  * **On a new token** (login/registration) — [signIn] writes memory first,
///    then storage.
///  * **On logout** — [signOut] wipes memory and storage.
class DriverAuthController extends AsyncNotifier<DriverAuthSession?> {
  @override
  Future<DriverAuthSession?> build() async {
    // Launch-time hydration: pull the saved session off disk into memory.
    return ref.watch(driverSessionStorageProvider).read();
  }

  /// The current session, read synchronously from memory (null if logged out
  /// or still loading).
  DriverAuthSession? get session => state.valueOrNull;

  /// The current bearer token, read synchronously from memory.
  String? get token => state.valueOrNull?.token;

  /// Records a freshly issued session: memory first (so the app reacts
  /// immediately), then persisted to secure storage.
  Future<void> signIn(DriverAuthSession newSession) async {
    state = AsyncData(newSession);
    await ref.read(driverSessionStorageProvider).write(newSession);
  }

  /// Clears the session from both memory and secure storage.
  Future<void> signOut() async {
    state = const AsyncData(null);
    await ref.read(driverSessionStorageProvider).clear();
  }
}

/// The app-wide driver session controller.
final driverAuthControllerProvider =
    AsyncNotifierProvider<DriverAuthController, DriverAuthSession?>(
      DriverAuthController.new,
    );
