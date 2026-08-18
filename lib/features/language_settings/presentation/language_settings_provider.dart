import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/settings_repository_provider.dart';
import '../data/language_settings_repository.dart';
import '../domain/app_locale.dart';
import '../domain/language_settings.dart';

final languageSettingsRepositoryProvider = Provider<LanguageSettingsRepository>((ref) {
  return LanguageSettingsRepository(ref.watch(settingsRepositoryProvider));
});

class LanguageSettingsNotifier extends Notifier<LanguageSettings> {
  @override
  LanguageSettings build() {
    return ref.watch(languageSettingsRepositoryProvider).read();
  }

  Future<void> setLocale(AppLocale locale) async {
    if (locale == state.locale) return;
    state = state.copyWith(locale: locale);
    await ref.read(languageSettingsRepositoryProvider).write(state);
  }
}

final languageSettingsProvider = NotifierProvider<LanguageSettingsNotifier, LanguageSettings>(
  LanguageSettingsNotifier.new,
);
