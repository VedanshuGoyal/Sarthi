import 'dart:ui' show Locale;

/// The language the driver picked for the app, or [system] to follow the
/// phone's (the default: the phone's language when it's Hindi or English,
/// otherwise English).
enum AppLanguage {
  system('system', null),
  english('en', Locale('en')),
  hindi('hi', Locale('hi'));

  const AppLanguage(this.storageValue, this.locale);

  /// How it's saved on the phone.
  final String storageValue;

  /// The locale to force, or null to follow the phone.
  final Locale? locale;

  /// Reads a saved value; anything unknown (or nothing) is [system].
  static AppLanguage fromStorage(String? value) =>
      values.firstWhere((l) => l.storageValue == value, orElse: () => system);

  /// The explicit choice for a locale's language — [english] for anything
  /// but Hindi, as the app falls back to English.
  static AppLanguage forLocale(Locale locale) =>
      locale.languageCode == 'hi' ? hindi : english;
}
