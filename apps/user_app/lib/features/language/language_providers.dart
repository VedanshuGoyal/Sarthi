import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/language_repository.dart';
import 'view_model/language_view_model.dart';

/// Where the language choice is saved. Overridden in tests.
final languageRepositoryProvider = Provider<LanguageRepository>((ref) {
  return SecureLanguageRepository();
});

/// The app-wide language; `MaterialApp` watches its [LanguageViewModel.locale].
final languageViewModelProvider = ChangeNotifierProvider<LanguageViewModel>((
  ref,
) {
  return LanguageViewModel(repository: ref.watch(languageRepositoryProvider))
    ..load();
});
