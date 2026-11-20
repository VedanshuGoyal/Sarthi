import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

import '../config/app_build.dart';

/// Where uncaught errors are reported: Firebase Crashlytics in the app
/// ([FirebaseCrashReporter]), a fake in tests.
///
/// Carries no personal data: nothing here sets a user id, phone number, name
/// or email. The only custom key is the opaque build number.
abstract interface class CrashReporter {
  /// Turns sending reports on or off. Crashlytics keeps the setting across
  /// launches.
  Future<void> setCollectionEnabled(bool enabled);

  /// Attaches [key] = [value] to every later report.
  Future<void> setCustomKey(String key, Object value);

  /// Reports an error the Flutter framework caught (build, layout, paint).
  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    required bool fatal,
  });

  /// Reports an error nothing in the app caught.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    required bool fatal,
  });
}

/// [CrashReporter] backed by Firebase Crashlytics.
class FirebaseCrashReporter implements CrashReporter {
  FirebaseCrashReporter(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  /// Starts Firebase and returns a reporter, or null where Firebase has no
  /// project: web, platforms other than Android (same reach as push), and
  /// builds without `android/app/google-services.json`.
  static Future<CrashReporter?> connect() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('crash reporting: off — Firebase is not configured ($e)');
      return null;
    }
    return FirebaseCrashReporter(FirebaseCrashlytics.instance);
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) =>
      _crashlytics.setCrashlyticsCollectionEnabled(enabled);

  @override
  Future<void> setCustomKey(String key, Object value) =>
      _crashlytics.setCustomKey(key, value);

  // Not Crashlytics' recordFlutterError: that also prints the error, and the
  // handler that was in place before ours already does.
  @override
  Future<void> recordFlutterError(
    FlutterErrorDetails details, {
    required bool fatal,
  }) => _crashlytics.recordError(
    details.exceptionAsString(),
    details.stack,
    reason: details.context
        ?.toStringDeep(minLevel: DiagnosticLevel.info)
        .trim(),
    information: details.informationCollector?.call() ?? const [],
    printDetails: false,
    fatal: fatal,
  );

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    required bool fatal,
  }) =>
      _crashlytics.recordError(error, stack, printDetails: false, fatal: fatal);
}

/// Crash reporting for one run of the app.
///
/// In a release build, [start] turns collection on and sends uncaught errors
/// to the [CrashReporter] as fatal: Flutter framework errors
/// ([FlutterError.onError]), errors that reach the platform dispatcher
/// ([PlatformDispatcher.onError]) and, through [recordZoneError], errors that
/// reach the app's guarded zone. Debug and profile builds turn collection off
/// and report nothing. Without Firebase it stays off and the app runs as
/// before.
class CrashReporting {
  CrashReporting({
    Future<CrashReporter?> Function()? connect,
    this.releaseMode = kReleaseMode,
    this.connectTimeout = const Duration(seconds: 5),
  }) : _connect = connect ?? FirebaseCrashReporter.connect;

  final Future<CrashReporter?> Function() _connect;

  /// Whether this is a release build; only release builds send reports.
  final bool releaseMode;

  /// How long [start] waits for Firebase before going on without it, so a
  /// slow start never holds up the first frame for long.
  final Duration connectTimeout;

  CrashReporter? _reporter;

  /// Where uncaught errors go; null while crash reporting is off.
  CrashReporter? get reporter => _reporter;

  /// Connects to the reporter and, in a release build, installs the error
  /// handlers. Never throws: on any failure crash reporting stays off.
  Future<void> start({PlatformDispatcher? dispatcher}) async {
    try {
      final reporter = await _connect().timeout(connectTimeout);
      if (reporter == null) return;
      // Set on every launch, as Crashlytics remembers it: a device that ran
      // a release build and then a debug one must stop sending.
      await reporter.setCollectionEnabled(releaseMode);
      if (!releaseMode) return;
      await reporter.setCustomKey('app_build', AppBuild.number);
      installCrashHandlers(reporter, dispatcher: dispatcher);
      _reporter = reporter;
    } catch (e) {
      debugPrint('crash reporting: off ($e)');
    }
  }

  /// An uncaught error from the app's guarded zone (`runZonedGuarded`),
  /// which never reaches [PlatformDispatcher.onError].
  void recordZoneError(Object error, StackTrace stack) {
    final reporter = _reporter;
    if (reporter == null) return;
    unawaited(_send(() => reporter.recordError(error, stack, fatal: true)));
  }
}

/// Sends uncaught errors to [reporter] as fatal, then hands them to the
/// handlers that were in place before, so console output stays as it was.
void installCrashHandlers(
  CrashReporter reporter, {
  PlatformDispatcher? dispatcher,
}) {
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(_send(() => reporter.recordFlutterError(details, fatal: true)));
    previousFlutterHandler?.call(details);
  };

  final platform = dispatcher ?? PlatformDispatcher.instance;
  final previousPlatformHandler = platform.onError;
  platform.onError = (error, stack) {
    unawaited(_send(() => reporter.recordError(error, stack, fatal: true)));
    // false: not handled here, so the engine still prints it.
    return previousPlatformHandler?.call(error, stack) ?? false;
  };
}

/// Runs one report. A report that fails is dropped, never rethrown: an error
/// from the error handler would come straight back to it.
Future<void> _send(Future<void> Function() record) async {
  try {
    await record();
  } catch (e) {
    debugPrint('crash reporting: report not sent ($e)');
  }
}
