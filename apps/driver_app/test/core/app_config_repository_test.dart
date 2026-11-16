import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:driver_app/core/config/app_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A backend whose `GET /app/config` answers [status] with [body]; [calls]
/// counts the requests.
http.Client _backend(int status, Object? body, {List<Uri>? calls}) =>
    MockClient((request) async {
      calls?.add(request.url);
      if (request.method == 'GET' && request.url.path == '/app/config') {
        return http.Response(body is String ? body : jsonEncode(body), status);
      }
      return http.Response('not found', 404);
    });

void main() {
  group('resolveSupportPhone', () {
    test('prefers the backend, then the build, then nothing', () {
      check(
        resolveSupportPhone(fromConfig: '+911111111111', fromBuild: '+912'),
      ).equals('+911111111111');
      check(
        resolveSupportPhone(fromConfig: '  ', fromBuild: '+912222222222'),
      ).equals('+912222222222');
      check(
        resolveSupportPhone(fromConfig: null, fromBuild: '+912222222222'),
      ).equals('+912222222222');
      check(resolveSupportPhone(fromConfig: null)).isNull();
      check(resolveSupportPhone(fromConfig: '', fromBuild: ' ')).isNull();
    });

    test('no number is baked into the build by default', () {
      // A public repo: the number must come from --dart-define or the server.
      check(supportPhoneFromBuild).isEmpty();
    });
  });

  group('AppConfigRepository.supportPhone', () {
    test("uses the backend's supportPhone", () async {
      final repo = AppConfigRepository(
        client: _backend(200, {'supportPhone': '+919000000001'}),
        fallbackSupportPhone: '+919000000002',
      );
      check(await repo.supportPhone()).equals('+919000000001');
    });

    test(
      'falls back to the build value when the endpoint is missing',
      () async {
        final repo = AppConfigRepository(
          client: _backend(404, 'not found'),
          fallbackSupportPhone: '+919000000002',
        );
        check(await repo.supportPhone()).equals('+919000000002');
      },
    );

    test('falls back when the config has no number', () async {
      final repo = AppConfigRepository(
        client: _backend(200, {'minAppVersion': '1.6.0'}),
        fallbackSupportPhone: '+919000000002',
      );
      check(await repo.supportPhone()).equals('+919000000002');
    });

    test('is null with neither, and never throws', () async {
      final repo = AppConfigRepository(
        client: MockClient((_) async => throw http.ClientException('down')),
        fallbackSupportPhone: '',
      );
      check(await repo.supportPhone()).isNull();
      final garbled = AppConfigRepository(
        client: _backend(200, '<html>'),
        fallbackSupportPhone: '',
      );
      check(await garbled.supportPhone()).isNull();
    });

    test('keeps a good read; retries a failed one', () async {
      final calls = <Uri>[];
      final good = AppConfigRepository(
        client: _backend(200, {'supportPhone': '+919000000001'}, calls: calls),
      );
      await good.supportPhone();
      await good.supportPhone();
      check(calls).length.equals(1);

      calls.clear();
      final failing = AppConfigRepository(
        client: _backend(503, 'down', calls: calls),
      );
      await failing.supportPhone();
      await failing.supportPhone();
      check(calls).length.equals(2);
    });
  });
}
