import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/settings_repository_provider.dart';
import '../data/connectivity_service.dart';
import '../data/network_settings_repository.dart';
import '../domain/active_network.dart';
import '../domain/cellular_usage.dart';
import '../domain/network_settings.dart';

final networkSettingsRepositoryProvider = Provider<NetworkSettingsRepository>((ref) {
  return NetworkSettingsRepository(ref.watch(settingsRepositoryProvider));
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) => ConnectivityService());

/// The live network the phone is on. Starts from a one-shot check so the first
/// read isn't `null` while waiting for the first change event — the policy
/// checks below run at "user tapped record" time and cannot wait.
final activeNetworkProvider = StreamProvider<ActiveNetwork>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  yield await service.current();
  yield* service.changes();
});

class NetworkSettingsNotifier extends Notifier<NetworkSettings> {
  @override
  NetworkSettings build() {
    return ref.watch(networkSettingsRepositoryProvider).read();
  }

  Future<void> _update(NetworkSettings next) async {
    if (next == state) return;
    state = next;
    await ref.read(networkSettingsRepositoryProvider).write(next);
  }

  Future<void> setPreferredNetwork(PreferredNetwork value) =>
      _update(state.copyWith(preferredNetwork: value));

  Future<void> setCellularDataCapMb(int? value) =>
      _update(state.copyWith(cellularDataCapMb: value, clearCap: value == null));

  Future<void> setWarnBeforeCap(bool value) => _update(state.copyWith(warnBeforeCap: value));
}

final networkSettingsProvider = NotifierProvider<NetworkSettingsNotifier, NetworkSettings>(
  NetworkSettingsNotifier.new,
);

/// Cumulative mobile-data usage, rolled over into the current calendar month
/// on read (see [CellularUsage]).
class CellularUsageNotifier extends Notifier<CellularUsage> {
  @override
  CellularUsage build() {
    return ref.watch(networkSettingsRepositoryProvider).readUsage(DateTime.now());
  }

  /// Adds bytes actually sent over mobile data. Called from the session as
  /// publisher stats arrive; a no-op for non-positive deltas so a counter
  /// reset natively (a new stream) can never subtract from the total.
  Future<void> add(int bytes) async {
    final next = state.plus(bytes);
    if (next == state) return;
    state = next;
    await ref.read(networkSettingsRepositoryProvider).writeUsage(next);
  }

  Future<void> reset() async {
    final next = CellularUsage.empty(DateTime.now());
    state = next;
    await ref.read(networkSettingsRepositoryProvider).writeUsage(next);
  }
}

final cellularUsageProvider = NotifierProvider<CellularUsageNotifier, CellularUsage>(
  CellularUsageNotifier.new,
);
