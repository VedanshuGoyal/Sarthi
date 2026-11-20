import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/core/config/app_build.dart';
import 'package:user_app/core/services/app_http_client.dart';
import 'package:user_app/features/auth/auth_controller.dart';
import 'package:user_app/features/auth/data/session_storage.dart';
import 'package:user_app/features/auth/domain/auth_session.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/update/data/app_config_repository.dart';
import 'package:user_app/features/update/domain/app_release.dart';
import 'package:user_app/features/update/update_providers.dart';
import 'package:user_app/features/update/view/update_gate.dart';
import 'package:user_app/features/update/view/update_required_screen.dart';
import 'package:user_app/features/update/view_model/update_gate_view_model.dart';
import 'package:user_app/l10n/l10n.dart';

const _updateRequired = {
  'error':
      'This version of MOJUD is out of date. Please install the latest '
      'version from apps.mojud.life to continue.',
  'code': 'update_required',
  'downloadUrl': 'https://apps.mojud.life/user',
};

String _config({int minBuild = 0, int latestBuild = 0}) => jsonEncode({
  'apps': {
    'user_app': {
      'minBuild': minBuild,
      'latestBuild': latestBuild,
      'downloadUrl': 'https://apps.mojud.life',
    },
    'driver_app': {
      'minBuild': 99,
      'latestBuild': 99,
      'downloadUrl': 'https://apps.mojud.life',
    },
  },
});

class _NoSession implements SessionStorage {
  @override
  Future<AuthSession?> read() async => null;
  @override
  Future<void> write(AuthSession session) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  group('AppHttpClient', () {
    test('adds its headers without overriding a request\'s own', () async {
      final seen = <Map<String, String>>[];
      final client = AppHttpClient(
        inner: MockClient((r) async {
          seen.add(r.headers);
          return http.Response('{}', 200);
        }),
        headers: const {'X-App': 'user_app', 'X-Build': '8'},
      );

      await client.get(Uri.parse('http://api/me/bookings'));
      await client.get(
        Uri.parse('http://api/me/bookings'),
        headers: {'X-Build': '9'},
      );

      check(seen[0]).deepEquals({'X-App': 'user_app', 'X-Build': '8'});
      check(seen[1]['X-Build']).equals('9');
    });

    test('a 426 update_required reports the download URL and still '
        'hands back the body', () async {
      final urls = <String?>[];
      final client = AppHttpClient(
        inner: MockClient(
          (_) async => http.Response(jsonEncode(_updateRequired), 426),
        ),
        onUpdateRequired: urls.add,
      );

      final response = await client.get(Uri.parse('http://api/me/bookings'));

      check(urls).deepEquals(['https://apps.mojud.life/user']);
      check(response.statusCode).equals(426);
      check(
        (jsonDecode(response.body) as Map)['error'] as String,
      ).startsWith('This version of MOJUD');
    });

    test('other replies and other 426s leave the gate alone', () async {
      final urls = <String?>[];
      for (final (status, body) in [
        (200, jsonEncode({'code': 'update_required'})),
        (426, 'Upgrade to TLS'),
        (426, jsonEncode({'code': 'something_else'})),
      ]) {
        final client = AppHttpClient(
          inner: MockClient((_) async => http.Response(body, status)),
          onUpdateRequired: urls.add,
        );
        await client.get(Uri.parse('http://api/x'));
      }
      check(urls).isEmpty();
    });
  });

  group('AppBuild', () {
    test('a test run is an unversioned build of the customer app', () {
      check(AppBuild.headers).deepEquals({'X-App': 'user_app', 'X-Build': '0'});
    });
  });

  group('AppRelease', () {
    test('build 0 is never too old; others are below minBuild only', () {
      const release = AppRelease(
        minBuild: 9,
        latestBuild: 10,
        downloadUrl: 'https://apps.mojud.life',
      );
      check(release.requiresUpdate(0)).isFalse();
      check(release.requiresUpdate(8)).isTrue();
      check(release.requiresUpdate(9)).isFalse();
    });
  });

  group('UpdateGateViewModel', () {
    UpdateGateViewModel gate(MockClient backend, {int build = 8}) =>
        UpdateGateViewModel(
          repository: AppConfigRepository(
            client: backend,
            baseUrl: 'http://api',
          ),
          build: build,
        );

    test('closes when /app/config lists a newer minimum', () async {
      final vm = gate(
        MockClient((r) async {
          check(r.url.path).equals('/app/config');
          return http.Response(_config(minBuild: 9, latestBuild: 9), 200);
        }),
      );

      await vm.check();

      check(vm.updateRequired).isTrue();
      check(vm.downloadUrl).equals('https://apps.mojud.life');
    });

    test('stays open at or above the minimum, and for build 0', () async {
      final backend = MockClient(
        (_) async => http.Response(_config(minBuild: 8), 200),
      );
      final current = gate(backend);
      final debug = gate(
        MockClient((_) async => http.Response(_config(minBuild: 9), 200)),
        build: 0,
      );

      await current.check();
      await debug.check();

      check(current.updateRequired).isFalse();
      check(debug.updateRequired).isFalse();
    });

    test('ignores a failed or unreadable config, and fetches once', () async {
      var calls = 0;
      for (final reply in [
        () => throw http.ClientException('offline'),
        () => http.Response('not json', 200),
        () => http.Response('{"error":"not found"}', 404),
      ]) {
        final vm = gate(
          MockClient((_) async {
            calls++;
            return reply();
          }),
        );
        await vm.check();
        await vm.check();
        check(vm.updateRequired).isFalse();
      }
      check(calls).equals(3);
    });

    test('require falls back to the default download page', () {
      final vm = gate(MockClient((_) async => http.Response('', 500)));
      var notified = 0;
      vm.addListener(() => notified++);

      vm.require();
      vm.require(); // already closed: no second rebuild

      check(vm.updateRequired).isTrue();
      check(vm.downloadUrl).equals(AppBuild.defaultDownloadUrl);
      check(notified).equals(1);
    });
  });

  group('backendClientProvider', () {
    test('sends the build headers, and a 426 closes the update gate', () async {
      final seen = <http.BaseRequest>[];
      final container = ProviderContainer(
        overrides: [
          sessionStorageProvider.overrideWithValue(_NoSession()),
          httpClientProvider.overrideWithValue(
            MockClient((r) async {
              seen.add(r);
              return http.Response(jsonEncode(_updateRequired), 426);
            }),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await container
          .read(bookingRepositoryProvider)
          .myBookings()
          .then<void>((_) {}, onError: (_) {});

      check(seen.single.headers['X-App']).equals('user_app');
      check(seen.single.headers['X-Build']).equals('${AppBuild.number}');
      final gate = container.read(updateGateProvider);
      check(gate.updateRequired).isTrue();
      check(gate.downloadUrl).equals('https://apps.mojud.life/user');
    });
  });

  group('UpdateGate', () {
    Future<void> pumpApp(WidgetTester tester, UpdateGateViewModel gate) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [updateGateProvider.overrideWith((ref) => gate)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: SkylineTheme.light(),
            builder: (context, child) => UpdateGate(child: child!),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('checks at startup and replaces the app when too old', (
      tester,
    ) async {
      final gate = UpdateGateViewModel(
        repository: AppConfigRepository(
          client: MockClient(
            (_) async => http.Response(_config(minBuild: 9), 200),
          ),
          baseUrl: 'http://api',
        ),
        build: 8,
      );

      await pumpApp(tester, gate);

      check(find.text('Home').evaluate()).isEmpty();
      check(find.text('Update MOJUD').evaluate()).length.equals(1);
      check(
        find.text('Download it from apps.mojud.life').evaluate(),
      ).length.equals(1);
    });

    testWidgets('leaves the app alone when the build is current', (
      tester,
    ) async {
      final gate = UpdateGateViewModel(
        repository: AppConfigRepository(
          client: MockClient(
            (_) async => http.Response(_config(minBuild: 8), 200),
          ),
          baseUrl: 'http://api',
        ),
        build: 8,
      );

      await pumpApp(tester, gate);

      check(find.text('Home').evaluate()).length.equals(1);

      // A 426 later, from any screen, still closes it.
      gate.require('https://apps.mojud.life');
      await tester.pumpAndSettle();
      check(find.text('Update MOJUD').evaluate()).length.equals(1);
    });
  });

  group('UpdateRequiredScreen', () {
    Future<void> pump(WidgetTester tester, UrlOpener open) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: SkylineTheme.light(),
          home: UpdateRequiredScreen(
            downloadUrl: 'https://apps.mojud.life',
            openUrl: open,
          ),
        ),
      );
    }

    testWidgets('the button opens the download page', (tester) async {
      final opened = <Uri>[];
      await pump(tester, (url) async {
        opened.add(url);
        return true;
      });

      await tester.tap(find.text('Get the latest version'));
      await tester.pump();

      check(opened).deepEquals([Uri.parse('https://apps.mojud.life')]);
    });

    testWidgets('says so when no browser opens, and copies the link', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester, (_) async => false);

      await tester.tap(find.text('Get the latest version'));
      await tester.pump();
      check(
        find.textContaining("Couldn't open a browser").evaluate(),
      ).length.equals(1);

      await tester.tap(find.text('Copy link'));
      await tester.pump();
      check(copied).equals('https://apps.mojud.life');
      check(find.text('Link copied').evaluate()).length.equals(1);
    });
  });
}
