import 'package:uuid/uuid.dart';

import '../../../core/persistence/secure_token_store.dart';
import '../../../core/persistence/settings_repository.dart';
import '../../video_settings/domain/video_overrides.dart';
import '../domain/stream_destination.dart';

/// Persists the destination list as one JSON array (via [SettingsRepository])
/// with each destination's stream key stored separately in
/// [SecureTokenStore], keyed by [StreamDestination.secureKeyId].
class DestinationsRepository {
  DestinationsRepository(this._settings, this._secureStore);

  static const _key = 'destinations';
  static const _uuid = Uuid();

  final SettingsRepository _settings;
  final SecureTokenStore _secureStore;

  List<StreamDestination> read() {
    final json = _settings.readJson(_key);
    if (json == null) return const [];
    final list = json['items'] as List<dynamic>? ?? const [];
    return list.map((e) => StreamDestination.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _writeAll(List<StreamDestination> destinations) {
    return _settings.writeJson(_key, {'items': destinations.map((d) => d.toJson()).toList()});
  }

  Future<String?> readStreamKey(String secureKeyId) => _secureStore.read(secureKeyId);

  /// Adds a destination and stores [streamKey] securely under a freshly
  /// generated id. Returns the saved destination.
  Future<StreamDestination> add({
    required StreamPlatform platform,
    required String displayName,
    required String rtmpUrl,
    required String streamKey,
  }) async {
    final secureKeyId = 'destination_key_${_uuid.v4()}';
    await _secureStore.write(secureKeyId, streamKey);

    final destination = StreamDestination(
      id: _uuid.v4(),
      platform: platform,
      displayName: displayName,
      rtmpUrl: rtmpUrl,
      secureKeyId: secureKeyId,
      enabled: true,
    );

    await _writeAll([...read(), destination]);
    return destination;
  }

  Future<void> remove(String id) async {
    final destinations = read();
    StreamDestination? target;
    for (final d in destinations) {
      if (d.id == id) target = d;
    }
    if (target == null) return;
    await _secureStore.delete(target.secureKeyId);
    await _writeAll(destinations.where((d) => d.id != id).toList());
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final destinations = read();
    await _writeAll([
      for (final d in destinations)
        if (d.id == id) d.copyWith(enabled: enabled) else d,
    ]);
  }

  /// Replaces a destination's per-destination video overrides wholesale.
  /// Pass [VideoOverrides.none] to drop back to the global video settings —
  /// there is no partial-merge form on purpose, since clearing one field has
  /// to be expressible and a merge can't distinguish "unset" from "absent".
  Future<void> setOverrides(String id, VideoOverrides overrides) async {
    final destinations = read();
    await _writeAll([
      for (final d in destinations)
        if (d.id == id) d.copyWith(overrides: overrides) else d,
    ]);
  }
}
