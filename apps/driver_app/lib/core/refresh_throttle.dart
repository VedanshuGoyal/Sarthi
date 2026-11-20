import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads the current time. A seam so tests can move time on without
/// waiting.
typedef Clock = DateTime Function();

/// The app's [Clock]. Overridden in tests.
final clockProvider = Provider<Clock>((ref) => DateTime.now);

/// Remembers when a view model last fetched, so a refresh nobody asked for
/// — the app coming back to the foreground — is skipped while the data is
/// still fresh. Every fetch counts, whatever started it (a push, a tab, a
/// poll), so a resume right after one doesn't fetch again, and rapid
/// switching in and out of the app doesn't hit the API each time.
class RefreshThrottle {
  RefreshThrottle({Clock? now, this.minGap = defaultGap})
    : _now = now ?? DateTime.now;

  /// How fresh data must be for a resume to skip re-reading it (my
  /// estimate: long enough to absorb app-switching, short enough that a
  /// driver coming back from Maps mid-trip sees a cancellation).
  static const Duration defaultGap = Duration(seconds: 15);

  final Clock _now;
  final Duration minGap;
  DateTime? _last;

  /// Records a fetch starting now. Marked at the start, so a failing
  /// server isn't asked again on every resume either.
  void mark() => _last = _now();

  /// Whether the last fetch started at least [minGap] ago, or never.
  bool get isStale {
    final last = _last;
    return last == null || !_now().isBefore(last.add(minGap));
  }
}
