import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// `context.l10n.someKey` — the driver's strings in the app's language.
///
/// Widgets use this, so they rebuild when the language changes. Strings live
/// in `lib/l10n/app_en.arb` (the template) and `app_hi.arb`; see
/// `docs/features/driver-app-hindi.md`.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Month and weekday names by number, from the `fmtMonthShort` and
/// `fmtWeekdayShort` select keys — instead of `intl`'s `DateFormat`, whose
/// locale data isn't loaded in unit tests.
extension CalendarNames on AppLocalizations {
  static const _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];
  static const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  /// "Mar" / "मार्च" for [month] 1–12, as in [DateTime.month].
  String monthShort(int month) => fmtMonthShort(_months[month - 1]);

  /// "Mon" / "सोम" for [weekday] 1–7 (Monday first), as in
  /// [DateTime.weekday].
  String weekdayShort(int weekday) => fmtWeekdayShort(_weekdays[weekday - 1]);
}

/// The strings for code that has no [BuildContext]: view models' and
/// repositories' messages for the driver, `RideFormat`, the notification
/// channel's name.
///
/// [L10nBinding] keeps it on the app's language. Until then — and in unit
/// tests, which build no app — it's English, the template.
abstract final class L10n {
  static AppLocalizations _current = _english;

  static final AppLocalizations _english = lookupAppLocalizations(
    const Locale('en'),
  );

  static AppLocalizations get current => _current;

  /// Points [current] at [strings]; [L10nBinding] calls it.
  static void bind(AppLocalizations strings) => _current = strings;

  /// Back to English.
  static void reset() => _current = _english;
}

/// Keeps [L10n.current] on the language this subtree is shown in. Sits in
/// `MaterialApp.builder`, below the app's [Localizations] and above every
/// screen, so it rebinds before any screen rebuilds for a new language.
class L10nBinding extends StatefulWidget {
  const L10nBinding({super.key, required this.child});

  final Widget child;

  @override
  State<L10nBinding> createState() => _L10nBindingState();
}

class _L10nBindingState extends State<L10nBinding> {
  @override
  void dispose() {
    L10n.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    L10n.bind(context.l10n);
    return widget.child;
  }
}
