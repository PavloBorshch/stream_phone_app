import '../../../core/persistence/settings_repository.dart';
import '../domain/cellular_usage.dart';
import '../domain/network_settings.dart';

/// Follows the `XSettings model + XSettingsRepository` pattern established by
/// `LanguageSettingsRepository` (PLAN.md Phase 2).
///
/// Cellular usage lives here too, under its own key: it is written far more
/// often than the settings themselves (every stats tick while publishing over
/// mobile data), and keeping it in the same blob would rewrite the user's
/// preferences on every tick.
class NetworkSettingsRepository {
  NetworkSettingsRepository(this._repository);

  static const _settingsKey = 'network_settings';
  static const _usageKey = 'cellular_usage';

  final SettingsRepository _repository;

  NetworkSettings read() {
    final json = _repository.readJson(_settingsKey);
    if (json == null) return NetworkSettings.defaults;
    return NetworkSettings.fromJson(json);
  }

  Future<void> write(NetworkSettings settings) {
    return _repository.writeJson(_settingsKey, settings.toJson());
  }

  CellularUsage readUsage(DateTime now) {
    final json = _repository.readJson(_usageKey);
    if (json == null) return CellularUsage.empty(now);
    return CellularUsage.fromJson(json).rolledOver(now);
  }

  Future<void> writeUsage(CellularUsage usage) {
    return _repository.writeJson(_usageKey, usage.toJson());
  }
}
