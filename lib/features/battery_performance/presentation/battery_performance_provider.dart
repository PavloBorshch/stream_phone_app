import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/settings_repository_provider.dart';
import '../data/battery_performance_repository.dart';
import '../data/battery_service.dart';
import '../data/device_health_platform.dart';
import '../domain/battery_performance_settings.dart';
import '../domain/device_health.dart';

final batteryPerformanceRepositoryProvider = Provider<BatteryPerformanceRepository>((ref) {
  return BatteryPerformanceRepository(ref.watch(settingsRepositoryProvider));
});

final batteryServiceProvider = Provider<BatteryService>((ref) => BatteryService());

final deviceHealthPlatformProvider = Provider<DeviceHealthPlatform>(
  (ref) => DeviceHealthPlatform(),
);

final batteryStatusProvider = StreamProvider<BatteryStatus>((ref) {
  return ref.watch(batteryServiceProvider).changes();
});

/// Live thermal state. Falls back to [ThermalStatus.unknown] rather than
/// surfacing an error where the native side isn't present — unknown already
/// means "don't throttle", which is the right behaviour for a build that
/// cannot report temperature.
final thermalStatusProvider = StreamProvider<ThermalStatus>((ref) async* {
  final platform = ref.watch(deviceHealthPlatformProvider);
  try {
    yield await platform.getStatus();
  } on MissingPluginException {
    yield ThermalStatus.unknown;
    return;
  } on PlatformException catch (error) {
    debugPrint('thermal getStatus failed: $error');
    yield ThermalStatus.unknown;
    return;
  }
  yield* platform.events().handleError((Object error) {
    debugPrint('thermal event stream error: $error');
  });
});

class BatteryPerformanceNotifier extends Notifier<BatteryPerformanceSettings> {
  @override
  BatteryPerformanceSettings build() {
    return ref.watch(batteryPerformanceRepositoryProvider).read();
  }

  Future<void> _update(BatteryPerformanceSettings next) async {
    if (next == state) return;
    state = next;
    await ref.read(batteryPerformanceRepositoryProvider).write(next);
  }

  Future<void> setBatteryGuard(PerformanceGuard value) =>
      _update(state.copyWith(batteryGuard: value));

  Future<void> setBatteryThresholdPercent(int value) =>
      _update(state.copyWith(batteryThresholdPercent: value));

  Future<void> setThermalGuard(PerformanceGuard value) =>
      _update(state.copyWith(thermalGuard: value));

  Future<void> setKeepScreenAwake(bool value) =>
      _update(state.copyWith(keepScreenAwake: value));
}

final batteryPerformanceProvider =
    NotifierProvider<BatteryPerformanceNotifier, BatteryPerformanceSettings>(
  BatteryPerformanceNotifier.new,
);
