import '../../../core/persistence/settings_repository.dart';
import '../domain/broadcast_target.dart';

/// Persists the user's broadcast-target selection (which of Leg A / Leg B /
/// both to feed from the capture session) so it survives an app restart.
/// Follows the `XSettings model + XSettingsRepository` pattern
/// (`LanguageSettingsRepository` is the reference instantiation) even though
/// the "model" here is a bare enum, for consistency with every other
/// settings domain.
class BroadcastTargetRepository {
  BroadcastTargetRepository(this._repository);

  static const _key = 'broadcast_target';

  final SettingsRepository _repository;

  BroadcastTarget read() {
    final json = _repository.readJson(_key);
    if (json == null) return BroadcastTarget.toServices;
    return BroadcastTarget.fromName(json['target'] as String?);
  }

  Future<void> write(BroadcastTarget target) {
    return _repository.writeJson(_key, {'target': target.name});
  }
}
