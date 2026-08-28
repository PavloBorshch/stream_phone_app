import '../../../core/persistence/settings_repository.dart';
import '../domain/battery_performance_settings.dart';

/// Follows the `XSettings model + XSettingsRepository` pattern established by
/// `LanguageSettingsRepository` (PLAN.md Phase 2).
class BatteryPerformanceRepository {
  BatteryPerformanceRepository(this._repository);

  static const _key = 'battery_performance_settings';

  final SettingsRepository _repository;

  BatteryPerformanceSettings read() {
    final json = _repository.readJson(_key);
    if (json == null) return BatteryPerformanceSettings.defaults;
    return BatteryPerformanceSettings.fromJson(json);
  }

  Future<void> write(BatteryPerformanceSettings settings) {
    return _repository.writeJson(_key, settings.toJson());
  }
}
