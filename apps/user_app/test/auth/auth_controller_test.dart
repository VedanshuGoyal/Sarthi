import 'package:checks/checks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/auth/auth_controller.dart';
import 'package:user_app/features/auth/data/session_storage.dart';
import 'package:user_app/features/auth/domain/auth_session.dart';
import 'package:user_app/features/auth/domain/auth_user.dart';

/// In-memory [SessionStorage] double so the controller can be tested without
/// the platform channel `flutter_secure_storage` needs.
class FakeSessionStorage implements SessionStorage {
  FakeSessionStorage([this._session]);
  AuthSession? _session;
  int writes = 0;
  int clears = 0;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async {
    _session = session;
    writes++;
  }

  @override
  Future<void> clear() async {
    _session = null;
    clears++;
  }
}

AuthSession _session(String token) => AuthSession(
  token: token,
  user: AuthUser(
    id: 'u1',
    phoneE164: '+919876543210',
    name: 'Asha Sharma',
    email: 'asha@example.com',
    dateOfBirth: DateTime(2000, 1, 1),
  ),
);

ProviderContainer _container(SessionStorage storage) {
  final container = ProviderContainer(
    overrides: [sessionStorageProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('AuthController', () {
    test('hydrates the saved session from storage on launch', () async {
      final container = _container(FakeSessionStorage(_session('saved-token')));

      final loaded = await container.read(authControllerProvider.future);
      check(loaded).isNotNull();
      check(loaded!.token).equals('saved-token');
      // Synchronous, in-memory reads are available once loaded.
      check(
        container.read(authControllerProvider.notifier).token,
      ).equals('saved-token');
    });

    test('starts logged out when storage is empty', () async {
      final container = _container(FakeSessionStorage());
      final loaded = await container.read(authControllerProvider.future);
      check(loaded).isNull();
    });

    test('signIn writes to memory and storage', () async {
      final storage = FakeSessionStorage();
      final container = _container(storage);
      await container.read(authControllerProvider.future); // finish loading

      final controller = container.read(authControllerProvider.notifier);
      await controller.signIn(_session('new-token'));

      check(controller.token).equals('new-token'); // memory
      check(storage.writes).equals(1); // storage
      check((await storage.read())!.token).equals('new-token');
    });

    test('signOut wipes memory and storage', () async {
      final storage = FakeSessionStorage(_session('live-token'));
      final container = _container(storage);
      await container.read(authControllerProvider.future);

      final controller = container.read(authControllerProvider.notifier);
      await controller.signOut();

      check(controller.token).isNull(); // memory wiped
      check(storage.clears).equals(1); // storage wiped
      check(await storage.read()).isNull();
    });
  });

  group('AuthSession JSON', () {
    test('round-trips through toJson/fromJson', () {
      final original = _session('tok-123');
      final restored = AuthSession.fromJson(original.toJson());
      check(restored.token).equals('tok-123');
      check(restored.user.id).equals('u1');
      check(restored.user.phoneE164).equals('+919876543210');
      check(restored.user.dateOfBirth).equals(DateTime(2000, 1, 1));
    });
  });
}
