import '../../../core/persistence/settings_repository.dart';
import '../domain/language_settings.dart';

/// The reference instantiation of the "XSettings model + XSettingsRepository"
/// pattern (PLAN.md Phase 2) that later settings domains (video, audio,
/// network, ...) should mirror.
class LanguageSettingsRepository {
  LanguageSettingsRepository(this._repository);

  static const _key = 'language_settings';

  final SettingsRepository _repository;

  LanguageSettings read() {
    final json = _repository.readJson(_key);
    if (json == null) return LanguageSettings.defaults;
    return LanguageSettings.fromJson(json);
  }

  Future<void> write(LanguageSettings settings) {
    return _repository.writeJson(_key, settings.toJson());
  }
}
