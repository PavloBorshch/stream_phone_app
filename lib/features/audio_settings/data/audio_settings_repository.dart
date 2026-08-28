import '../../../core/persistence/settings_repository.dart';
import '../domain/audio_settings.dart';

/// Follows the `XSettings model + XSettingsRepository` pattern established by
/// `LanguageSettingsRepository` (PLAN.md Phase 2).
class AudioSettingsRepository {
  AudioSettingsRepository(this._repository);

  static const _key = 'audio_settings';

  final SettingsRepository _repository;

  AudioSettings read() {
    final json = _repository.readJson(_key);
    if (json == null) return AudioSettings.defaults;
    return AudioSettings.fromJson(json);
  }

  Future<void> write(AudioSettings settings) {
    return _repository.writeJson(_key, settings.toJson());
  }
}
