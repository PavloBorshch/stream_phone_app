import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/settings_repository_provider.dart';
import '../data/broadcast_target_repository.dart';

/// The persistence-layer provider for [BroadcastTargetRepository]. There is
/// deliberately no separate `Notifier<BroadcastTarget>` alongside it (unlike
/// `AudioSettingsNotifier`/`LanguageSettingsNotifier`): the live value the UI
/// reads and reacts to is `StreamSessionState.broadcastTarget`, owned by
/// `StreamSessionNotifier` (same place `CaptureMode` lives) since starting a
/// stream needs to reason about it alongside PC-connection and destination
/// state already tracked there. This provider exists only so
/// `StreamSessionNotifier` can read/write the persisted value.
final broadcastTargetRepositoryProvider = Provider<BroadcastTargetRepository>((ref) {
  return BroadcastTargetRepository(ref.watch(settingsRepositoryProvider));
});
