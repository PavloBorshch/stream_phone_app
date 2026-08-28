import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository_provider.dart';
import 'package:stream_phone_cam/features/battery_performance/data/battery_service.dart';
import 'package:stream_phone_cam/features/battery_performance/domain/battery_performance_settings.dart';
import 'package:stream_phone_cam/features/battery_performance/domain/device_health.dart';
import 'package:stream_phone_cam/features/battery_performance/domain/performance_guard_decision.dart';
import 'package:stream_phone_cam/features/battery_performance/presentation/battery_performance_provider.dart';

void main() {
  const flat = BatteryStatus(levelPercent: 5, isOnPower: false);
  const charging = BatteryStatus(levelPercent: 5, isOnPower: true);
  const healthy = BatteryStatus(levelPercent: 90, isOnPower: false);

  PerformanceGuardDecision evaluate({
    BatteryPerformanceSettings settings = BatteryPerformanceSettings.defaults,
    BatteryStatus battery = healthy,
    ThermalStatus thermal = ThermalStatus.none,
  }) {
    return PerformanceGuardDecision.evaluate(
      settings: settings,
      battery: battery,
      thermal: thermal,
    );
  }

  group('thermal guard', () {
    test('does nothing while the device is merely warm', () {
      // "moderate" is normal under sustained recording; throttling on it would
      // mean permanently degraded quality on most phones.
      expect(evaluate(thermal: ThermalStatus.moderate).isConstrained, isFalse);
      expect(evaluate(thermal: ThermalStatus.light).isConstrained, isFalse);
    });

    test('throttles once the SoC is throttling itself', () {
      final decision = evaluate(thermal: ThermalStatus.severe);

      expect(decision.ceilingScale, PerformanceGuardDecision.throttledScale);
      expect(decision.frameRateCap, PerformanceGuardDecision.throttledFrameRate);
      expect(decision.shouldStop, isFalse);
      expect(decision.reason, contains('hot'));
    });

    test('unknown thermal state never throttles', () {
      // A device that cannot report temperature must not be assumed hot.
      expect(evaluate(thermal: ThermalStatus.unknown).isConstrained, isFalse);
    });

    test('can be told to stop the stream instead', () {
      final decision = evaluate(
        settings: BatteryPerformanceSettings.defaults
            .copyWith(thermalGuard: PerformanceGuard.stopStream),
        thermal: ThermalStatus.critical,
      );

      expect(decision.shouldStop, isTrue);
      expect(decision.reason, contains('too hot'));
    });

    test('can be switched off entirely', () {
      final decision = evaluate(
        settings:
            BatteryPerformanceSettings.defaults.copyWith(thermalGuard: PerformanceGuard.off),
        thermal: ThermalStatus.emergency,
      );

      expect(decision, PerformanceGuardDecision.unconstrained);
    });
  });

  group('battery guard', () {
    test('throttles below the threshold on battery', () {
      final decision = evaluate(battery: flat);

      expect(decision.ceilingScale, PerformanceGuardDecision.throttledScale);
      expect(decision.reason, contains('5%'));
    });

    test('is skipped entirely while charging', () {
      // 5% and rising is not an emergency; the phone is plugged in.
      expect(evaluate(battery: charging).isConstrained, isFalse);
    });

    test('respects the configured threshold', () {
      const battery = BatteryStatus(levelPercent: 18, isOnPower: false);

      expect(evaluate(battery: battery).isConstrained, isFalse);
      expect(
        evaluate(
          settings: BatteryPerformanceSettings.defaults.copyWith(batteryThresholdPercent: 20),
          battery: battery,
        ).isConstrained,
        isTrue,
      );
    });

    test('can be told to stop the stream instead', () {
      final decision = evaluate(
        settings: BatteryPerformanceSettings.defaults
            .copyWith(batteryGuard: PerformanceGuard.stopStream),
        battery: flat,
      );

      expect(decision.shouldStop, isTrue);
    });
  });

  test('thermal takes precedence over battery', () {
    // On a charger the battery guard cannot fire at all, so thermal has to be
    // checked first or an overheating charging phone would never throttle.
    final decision = evaluate(
      settings: BatteryPerformanceSettings.defaults.copyWith(
        batteryGuard: PerformanceGuard.stopStream,
      ),
      battery: flat,
      thermal: ThermalStatus.severe,
    );

    expect(decision.shouldStop, isFalse);
    expect(decision.reason, contains('hot'));
  });

  test('a healthy device is left completely alone', () {
    expect(evaluate(), PerformanceGuardDecision.unconstrained);
    expect(PerformanceGuardDecision.unconstrained.isConstrained, isFalse);
  });

  group('settings', () {
    test('survives a JSON round trip', () {
      const settings = BatteryPerformanceSettings(
        batteryGuard: PerformanceGuard.stopStream,
        batteryThresholdPercent: 30,
        thermalGuard: PerformanceGuard.off,
        keepScreenAwake: false,
      );

      expect(BatteryPerformanceSettings.fromJson(settings.toJson()), settings);
    });

    test('persists for the next session', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = await SettingsRepository.create();

      ProviderContainer build() {
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        return container;
      }

      await build().read(batteryPerformanceProvider.notifier).setKeepScreenAwake(false);

      expect(build().read(batteryPerformanceProvider).keepScreenAwake, isFalse);
    });
  });
}
