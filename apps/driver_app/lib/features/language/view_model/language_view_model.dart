import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import '../data/language_repository.dart';
import '../domain/app_language.dart';

/// The app's language: the phone's until the driver picks one, then theirs
/// — saved on the phone, so the app opens in it next time.
class LanguageViewModel extends ChangeNotifier {
  LanguageViewModel({required this._repository});

  final LanguageRepository _repository;

  AppLanguage _language = AppLanguage.system;
  bool _disposed = false;

  /// What the driver picked; [AppLanguage.system] until they pick.
  AppLanguage get language => _language;

  /// The locale `MaterialApp` should force, or null to follow the phone.
  Locale? get locale => _language.locale;

  /// Reads the saved choice. A choice made meanwhile wins.
  Future<void> load() async {
    final saved = await _repository.read();
    if (_disposed || _language != AppLanguage.system) return;
    _set(saved);
  }

  /// Switches the app to [language] at once and saves it. A failed save
  /// only means the next launch follows the phone again.
  Future<void> select(AppLanguage language) async {
    _set(language);
    try {
      await _repository.write(language);
    } catch (_) {
      // Keystore unavailable: the switch still holds for this session.
    }
  }

  void _set(AppLanguage language) {
    if (language == _language) return;
    _language = language;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
