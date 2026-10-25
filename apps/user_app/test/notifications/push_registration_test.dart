import 'dart:async';
import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/core/services/push_service.dart';
import 'package:user_app/features/notifications/data/push_token_repository.dart';
import 'package:user_app/features/notifications/push_registration.dart';

/// A push service with a fixed token and a hand-driven refresh stream.
class _FakePush extends PushService {
  _FakePush(this._token) : super.off();

  final String? _token;
  final refreshes = StreamController<String>.broadcast();
  bool deleted = false;

  @override
  Future<String?> token() async => _token;

  @override
  Stream<String> tokenRefreshes() => refreshes.stream;

  @override
  Future<void> deleteToken() async => deleted = true;
}

void main() {
  late List<http.Request> requests;
  late int status;

  PushTokenRepository repository() => PushTokenRepository(
    baseUrl: 'http://api.test',
    tokenGetter: () => 'session-1',
    client: MockClient((request) async {
      requests.add(request);
      return http.Response('', status);
    }),
  );

  setUp(() {
    requests = [];
    status = 204;
  });

  test('start registers the token, and again when FCM rotates it', () async {
    final push = _FakePush('fcm-1');
    final registration = PushRegistration(push: push, repository: repository());

    await registration.start();
    push.refreshes.add('fcm-2');
    await pumpEventQueue();

    check(
      requests.map((r) => '${r.method} ${r.url.path}'),
    ).deepEquals(['PUT /me/push-token', 'PUT /me/push-token']);
    check(
      requests.map((r) => jsonDecode(r.body)['token']),
    ).deepEquals(['fcm-1', 'fcm-2']);
    check(requests.first.headers['Authorization']).equals('Bearer session-1');
  });

  test('stop withdraws the latest token and invalidates it', () async {
    final push = _FakePush('fcm-1');
    final registration = PushRegistration(push: push, repository: repository());
    await registration.start();
    push.refreshes.add('fcm-2');
    await pumpEventQueue();
    requests.clear();

    await registration.stop();

    check(requests.single.method).equals('DELETE');
    check(jsonDecode(requests.single.body)['token']).equals('fcm-2');
    check(push.deleted).isTrue();
  });

  test('a server failure or no Firebase never throws', () async {
    status = 500;
    await PushRegistration(
      push: _FakePush('fcm-1'),
      repository: repository(),
    ).start();
    check(requests).length.equals(1);

    requests.clear();
    final off = PushRegistration(
      push: _FakePush(null),
      repository: repository(),
    );
    await off.start();
    await off.stop();
    check(requests).isEmpty();
  });

  test('PushService.off stays off', () async {
    final push = PushService.off();
    check(await push.ready).isFalse();
    check(await push.token()).isNull();
    check(await push.takeLaunchTap()).isNull();
  });
}
