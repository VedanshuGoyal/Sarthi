import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/services/app_http_client.dart';
import 'data/session_storage.dart';
import 'domain/auth_session.dart';

/// The durable session store (secure storage). Overridden in tests with a fake.
final sessionStorageProvider = Provider<SessionStorage>((ref) {
  return SecureSessionStorage();
});

/// App-wide authentication state and the single source of truth for the current
/// session.
///
/// It keeps the session in memory for instant, synchronous reads while mirroring
/// every change to secure storage:
///
///  * **On launch** — [build] reads the persisted session asynchronously and
///    loads it into memory (the returned [AsyncValue] is `loading` until then).
///  * **At runtime** — [token] / [session] read straight from memory, no await.
///  * **On a new token** (login/registration) — [signIn] writes memory first,
///    then storage.
///  * **On logout** — [signOut] wipes memory and storage.
class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    // Launch-time hydration: pull the saved session off disk into memory.
    return ref.watch(sessionStorageProvider).read();
  }

  /// The current session, read synchronously from memory (null if logged out or
  /// still loading).
  AuthSession? get session => state.valueOrNull;

  /// The current bearer token, read synchronously from memory.
  String? get token => state.valueOrNull?.token;

  /// Records a freshly issued session: memory first (so the app reacts
  /// immediately), then persisted to secure storage.
  Future<void> signIn(AuthSession newSession) async {
    state = AsyncData(newSession);
    await ref.read(sessionStorageProvider).write(newSession);
  }

  /// Clears the session from both memory and secure storage.
  Future<void> signOut() async {
    state = const AsyncData(null);
    await ref.read(sessionStorageProvider).clear();
  }
}

/// The app-wide session controller.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

/// The raw HTTP transport under [backendClientProvider] and
/// [thirdPartyClientProvider]. Overridden in tests with a mock.
final httpClientProvider = Provider<http.Client>((ref) => http.Client());

/// The client for every call to the MOJUD backend: time-limited, and a 401
/// to the current session signs the customer out (it expired or was
/// revoked). A 401 for an older session's token — a request still in flight
/// across a sign-out — is ignored.
final backendClientProvider = Provider<http.Client>((ref) {
  return AppHttpClient(
    inner: ref.watch(httpClientProvider),
    onSessionRejected: (token) {
      final auth = ref.read(authControllerProvider.notifier);
      if (auth.token == token) auth.signOut();
    },
  );
});

/// The client for third-party APIs (Ola Maps, Google Routes): time-limited
/// only — their 401s say nothing about our session.
final thirdPartyClientProvider = Provider<http.Client>((ref) {
  return AppHttpClient(inner: ref.watch(httpClientProvider));
});
