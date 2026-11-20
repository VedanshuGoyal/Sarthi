import 'package:checks/checks.dart';
import 'package:driver_app/core/location_providers.dart';
import 'package:driver_app/core/services/push_service.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/language/data/language_repository.dart';
import 'package:driver_app/features/language/domain/app_language.dart';
import 'package:driver_app/features/language/language_providers.dart';
import 'package:driver_app/features/language/view/language_switch.dart';
import 'package:driver_app/features/language/view_model/language_view_model.dart';
import 'package:driver_app/features/notifications/notification_providers.dart';
import 'package:driver_app/l10n/l10n.dart';
import 'package:driver_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../rides/fakes.dart';

/// The language choice in memory; [failWrites] makes saving throw.
class _Languages implements LanguageRepository {
  _Languages([this.saved = AppLanguage.system]);

  AppLanguage saved;
  bool failWrites = false;
  int writes = 0;

  @override
  Future<AppLanguage> read() async => saved;

  @override
  Future<void> write(AppLanguage language) async {
    writes++;
    if (failWrites) throw Exception('keystore unavailable');
    saved = language;
  }
}

/// Nobody signed in: the app opens on the start screen.
class _NoSession implements DriverSessionStorage {
  @override
  Future<DriverAuthSession?> read() async => null;
  @override
  Future<void> write(DriverAuthSession session) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  group('AppLanguage', () {
    test('reads what was saved; anything else follows the phone', () {
      check(AppLanguage.fromStorage('en')).equals(AppLanguage.english);
      check(AppLanguage.fromStorage('hi')).equals(AppLanguage.hindi);
      check(AppLanguage.fromStorage(null)).equals(AppLanguage.system);
      check(AppLanguage.fromStorage('ta')).equals(AppLanguage.system);
      check(AppLanguage.system.locale).isNull();
      check(AppLanguage.hindi.locale).equals(const Locale('hi'));
    });

    test('a locale other than Hindi is shown as English', () {
      check(
        AppLanguage.forLocale(const Locale('hi', 'IN')),
      ).equals(AppLanguage.hindi);
      check(
        AppLanguage.forLocale(const Locale('ta')),
      ).equals(AppLanguage.english);
    });
  });

  group('LanguageViewModel', () {
    test('follows the phone until it loads a saved choice', () async {
      final vm = LanguageViewModel(repository: _Languages(AppLanguage.hindi));
      addTearDown(vm.dispose);
      check(vm.language).equals(AppLanguage.system);
      check(vm.locale).isNull();

      await vm.load();

      check(vm.language).equals(AppLanguage.hindi);
      check(vm.locale).equals(const Locale('hi'));
    });

    test('switches at once and saves the choice', () async {
      final repo = _Languages();
      final vm = LanguageViewModel(repository: repo);
      addTearDown(vm.dispose);
      var notified = 0;
      vm.addListener(() => notified++);

      final saving = vm.select(AppLanguage.hindi);
      check(vm.language).equals(AppLanguage.hindi);
      check(notified).equals(1);
      await saving;

      check(repo.saved).equals(AppLanguage.hindi);
    });

    test('a choice made while loading beats the saved one', () async {
      final vm = LanguageViewModel(repository: _Languages(AppLanguage.english));
      addTearDown(vm.dispose);

      final loading = vm.load();
      await vm.select(AppLanguage.hindi);
      await loading;

      check(vm.language).equals(AppLanguage.hindi);
    });

    test('a failed save still switches for this session', () async {
      final repo = _Languages()..failWrites = true;
      final vm = LanguageViewModel(repository: repo);
      addTearDown(vm.dispose);

      await vm.select(AppLanguage.hindi);

      check(repo.writes).equals(1);
      check(vm.language).equals(AppLanguage.hindi);
    });
  });

  testWidgets('the Account switch changes the language both ways', (
    tester,
  ) async {
    final languages = _Languages();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [languageRepositoryProvider.overrideWithValue(languages)],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: SkylineTheme.light(),
            locale: ref.watch(
              languageViewModelProvider.select((vm) => vm.locale),
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: LanguageSwitch()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    check(find.text('Language · भाषा').evaluate()).isNotEmpty();
    check(
      find.text('Same as your phone. Pick one to change it.').evaluate(),
    ).isNotEmpty();

    await tester.tap(find.text('हिंदी'));
    await tester.pumpAndSettle();
    check(find.text('भाषा · Language').evaluate()).isNotEmpty();
    check(languages.saved).equals(AppLanguage.hindi);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    check(find.text('Language · भाषा').evaluate()).isNotEmpty();
    check(languages.saved).equals(AppLanguage.english);
    // An explicit pick: no longer "same as your phone".
    check(
      find.text('Same as your phone. Pick one to change it.').evaluate(),
    ).isEmpty();
  });

  group('the app', () {
    late _Languages languages;

    setUp(() => languages = _Languages());
    tearDown(L10n.reset);

    Future<void> pumpApp(WidgetTester tester, {Locale? phone}) async {
      if (phone != null) {
        tester.platformDispatcher.localesTestValue = [phone];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            httpClientProvider.overrideWithValue(
              MockClient((_) async => http.Response('{}', 404)),
            ),
            driverSessionStorageProvider.overrideWithValue(_NoSession()),
            pushServiceProvider.overrideWithValue(PushService.off()),
            locationServiceProvider.overrideWithValue(FakeLocationService()),
            languageRepositoryProvider.overrideWithValue(languages),
          ],
          child: const SarthiDriverApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens in Hindi on a Hindi phone', (tester) async {
      await pumpApp(tester, phone: const Locale('hi', 'IN'));

      check(find.text('ड्राइविंग शुरू करें').evaluate()).isNotEmpty();
      check(L10n.current.localeName).equals('hi');
    });

    testWidgets('opens in English on a phone in any other language', (
      tester,
    ) async {
      await pumpApp(tester, phone: const Locale('ta', 'IN'));

      check(find.text('Start Driving').evaluate()).isNotEmpty();
      check(L10n.current.localeName).equals('en');
    });

    testWidgets('a saved choice beats the phone', (tester) async {
      languages.saved = AppLanguage.english;
      await pumpApp(tester, phone: const Locale('hi', 'IN'));

      check(find.text('Start Driving').evaluate()).isNotEmpty();
    });

    testWidgets('the start screen switches to Hindi and remembers it', (
      tester,
    ) async {
      await pumpApp(tester, phone: const Locale('en', 'IN'));
      check(find.text('Start Driving').evaluate()).isNotEmpty();

      await tester.tap(find.byIcon(Icons.translate_rounded));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<AppLanguage>, 'हिंदी'),
      );
      await tester.pumpAndSettle();

      check(find.text('ड्राइविंग शुरू करें').evaluate()).isNotEmpty();
      check(L10n.current.localeName).equals('hi');
      check(languages.saved).equals(AppLanguage.hindi);
    });
  });
}
