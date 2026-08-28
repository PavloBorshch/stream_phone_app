import '../../../core/persistence/settings_repository.dart';
import '../domain/video_settings.dart';

/// Follows the `XSettings model + XSettingsRepository` pattern established by
/// `LanguageSettingsRepository` (PLAN.md Phase 2).
class VideoSettingsRepository {
  VideoSettingsRepository(this._repository);

  static const _key = 'video_settings';

  final SettingsRepository _repository;

  VideoSettings read() {
    final json = _repository.readJson(_key);
    if (json == null) return VideoSettings.defaults;
    return VideoSettings.fromJson(json);
  }

  Future<void> write(VideoSettings settings) {
    return _repository.writeJson(_key, settings.toJson());
  }
}
