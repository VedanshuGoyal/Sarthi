import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/config/app_build.dart';
import 'package:user_app/core/services/crash_reporting.dart';

/// Records what would have gone to Crashlytics.
class FakeCrashReporter implements CrashReporter {
  FakeCrashReporter({this.failReports = false});

  /// Every report throws, like a broken platform channel.
  final bool failReports;

  final collection = <bool>[];
  final keys = <String, Object>{};
  final flutterErrors = <({FlutterErrorDetails details, bool fatal})>[];
  final errors = <({Object error, StackTrace? stack, bool fatal})>[];

  @override
  Future<void> setCollectionEnabled(bool enabled) async =>
      collection.add(enabled);

  @override
  Future<void> setCustomKey(String key, Object value) async =>
      keys[key] = value;

  @override
  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    required bool fatal,
  }) async {
    if (failReports) throw StateError('channel down');
    flutterErrors.add((details: details, fatal: fatal));
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    required bool fatal,
  }) async {
    if (failReports) throw StateError('channel down');
    errors.add((error: error, stack: stack, fatal: fatal));
  }
}

/// Puts the global error handlers back after the test, whatever it set.
void restoreErrorHandlersAfterTest() {
  final flutterHandler = FlutterError.onError;
  final platformHandler = PlatformDispatcher.instance.onError;
  addTearDown(() {
    FlutterError.onError = flutterHandler;
    PlatformDispatcher.instance.onError = platformHandler;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final details = FlutterErrorDetails(exception: StateError('build failed'));
  final stack = StackTrace.current;

  group('installCrashHandlers', () {
    setUp(restoreErrorHandlersAfterTest);

    test('reports Flutter errors as fatal and still runs the previous '
        'handler', () async {
      final printed = <FlutterErrorDetails>[];
      FlutterError.onError = printed.add;
      final reporter = FakeCrashReporter();

      installCrashHandlers(reporter);
      FlutterError.onError!(details);
      await pumpEventQueue();

      check(reporter.flutterErrors).single
        ..has((r) => r.details, 'details').identicalTo(details)
        ..has((r) => r.fatal, 'fatal').isTrue();
      check(printed).single.identicalTo(details);
    });

    test('reports platform errors as fatal and leaves them unhandled, so '
        'the engine still prints them', () async {
      PlatformDispatcher.instance.onError = null;
      final reporter = FakeCrashReporter();
      final error = StateError('async failure');

      installCrashHandlers(reporter);
      final handled = PlatformDispatcher.instance.onError!(error, stack);
      await pumpEventQueue();

      check(handled).isFalse();
      check(reporter.errors).single
        ..has((r) => r.error, 'error').identicalTo(error)
        ..has((r) => r.stack, 'stack').identicalTo(stack)
        ..has((r) => r.fatal, 'fatal').isTrue();
    });

    test(
      'a platform handler already in place still runs and decides',
      () async {
        final seen = <Object>[];
        PlatformDispatcher.instance.onError = (error, _) {
          seen.add(error);
          return true;
        };
        final reporter = FakeCrashReporter();
        final error = StateError('async failure');

        installCrashHandlers(reporter);
        final handled = PlatformDispatcher.instance.onError!(error, stack);
        await pumpEventQueue();

        check(handled).isTrue();
        check(seen).single.identicalTo(error);
        check(reporter.errors).length.equals(1);
      },
    );

    test('a report that fails never throws out of the handlers', () async {
      final printed = <FlutterErrorDetails>[];
      FlutterError.onError = printed.add;
      PlatformDispatcher.instance.onError = null;

      installCrashHandlers(FakeCrashReporter(failReports: true));
      FlutterError.onError!(details);
      final handled = PlatformDispatcher.instance.onError!(
        StateError('async failure'),
        stack,
      );
      await pumpEventQueue();

      check(printed).single.identicalTo(details);
      check(handled).isFalse();
    });
  });

  group('CrashReporting.start', () {
    setUp(restoreErrorHandlersAfterTest);

    test('a debug or profile build turns collection off and reports '
        'nothing', () async {
      final flutterHandler = FlutterError.onError;
      final platformHandler = PlatformDispatcher.instance.onError;
      final reporter = FakeCrashReporter();
      final reporting = CrashReporting(
        connect: () async => reporter,
        releaseMode: false,
      );

      await reporting.start();
      reporting.recordZoneError(StateError('zone'), stack);
      await pumpEventQueue();

      check(reporter.collection).deepEquals([false]);
      check(reporter.keys).isEmpty();
      check(reporter.errors).isEmpty();
      check(reporting.reporter).isNull();
      check(FlutterError.onError).equals(flutterHandler);
      check(PlatformDispatcher.instance.onError).equals(platformHandler);
    });

    test('the default follows the build mode, so tests (debug) never '
        'collect', () async {
      final reporter = FakeCrashReporter();

      await CrashReporting(connect: () async => reporter).start();

      check(kReleaseMode).isFalse();
      check(reporter.collection).deepEquals([false]);
    });

    test('a release build turns collection on, tags only the build number '
        'and reports uncaught errors', () async {
      final printed = <FlutterErrorDetails>[];
      FlutterError.onError = printed.add;
      final reporter = FakeCrashReporter();
      final reporting = CrashReporting(
        connect: () async => reporter,
        releaseMode: true,
      );
      final zoneError = StateError('zone');

      await reporting.start();
      FlutterError.onError!(details);
      reporting.recordZoneError(zoneError, stack);
      await pumpEventQueue();

      check(reporter.collection).deepEquals([true]);
      check(reporter.keys).deepEquals({'app_build': AppBuild.number});
      check(reporting.reporter).isNotNull().identicalTo(reporter);
      check(
        reporter.flutterErrors,
      ).single.has((r) => r.fatal, 'fatal').isTrue();
      check(reporter.errors).single
        ..has((r) => r.error, 'error').identicalTo(zoneError)
        ..has((r) => r.fatal, 'fatal').isTrue();
      check(printed).single.identicalTo(details);
    });

    test('without Firebase the app starts as before and nothing is '
        'reported', () async {
      final flutterHandler = FlutterError.onError;
      final reporting = CrashReporting(
        connect: () async => null,
        releaseMode: true,
      );

      await reporting.start();
      reporting.recordZoneError(StateError('zone'), stack);

      check(reporting.reporter).isNull();
      check(FlutterError.onError).equals(flutterHandler);
    });

    test('a Firebase start that fails or hangs leaves reporting off', () async {
      final failing = CrashReporting(
        connect: () async => throw StateError('no google-services.json'),
        releaseMode: true,
      );
      final hanging = CrashReporting(
        connect: () => Completer<CrashReporter?>().future,
        releaseMode: true,
        connectTimeout: const Duration(milliseconds: 10),
      );

      await failing.start();
      await hanging.start();

      check(failing.reporter).isNull();
      check(hanging.reporter).isNull();
    });
  });

  group('FirebaseCrashReporter.connect', () {
    test('is off where Firebase has no project to start', () async {
      // Android without a native Firebase app, as in a build without
      // google-services.json: Firebase.initializeApp fails.
      check(await FirebaseCrashReporter.connect()).isNull();

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      check(await FirebaseCrashReporter.connect()).isNull();
    });
  });
}
