import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository_provider.dart';
import 'package:stream_phone_cam/features/network_settings/data/network_settings_repository.dart';
import 'package:stream_phone_cam/features/network_settings/domain/active_network.dart';
import 'package:stream_phone_cam/features/network_settings/domain/cellular_usage.dart';
import 'package:stream_phone_cam/features/network_settings/domain/network_settings.dart';
import 'package:stream_phone_cam/features/network_settings/presentation/network_settings_provider.dart';

final _january = DateTime(2026, 1);

void main() {
  late SettingsRepository settings;

  /// Writes usage through a throwaway container, standing in for a previous
  /// run of the app.
  Future<void> addUsageThenClose(int bytes) async {
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
    );
    await container.read(cellularUsageProvider.notifier).add(bytes);
    container.dispose();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsRepository.create();
  });

  group('ActiveNetwork.fromConnectivity', () {
    test('an unmetered transport wins when several are reported at once', () {
      // A phone holding Wi-Fi and mobile simultaneously routes over Wi-Fi, so
      // treating the pair as metered would refuse free streaming.
      expect(
        ActiveNetwork.fromConnectivity([ConnectivityResult.wifi, ConnectivityResult.mobile]),
        ActiveNetwork.wifi,
      );
      expect(
        ActiveNetwork.fromConnectivity([ConnectivityResult.ethernet, ConnectivityResult.mobile]),
        ActiveNetwork.ethernet,
      );
    });

    test('mobile alone is metered', () {
      final network = ActiveNetwork.fromConnectivity([ConnectivityResult.mobile]);
      expect(network, ActiveNetwork.cellular);
      expect(network.isMetered, isTrue);
    });

    test('satellite rides along with mobile and stays metered', () {
      expect(
        ActiveNetwork.fromConnectivity([
          ConnectivityResult.mobile,
          ConnectivityResult.satellite,
        ]),
        ActiveNetwork.cellular,
      );
    });

    test('an empty or none result is offline', () {
      expect(ActiveNetwork.fromConnectivity([]), ActiveNetwork.none);
      expect(ActiveNetwork.fromConnectivity([ConnectivityResult.none]), ActiveNetwork.none);
    });

    test('an unrecognised transport is not assumed to be metered', () {
      // Guessing "metered" here would silently block streaming over a VPN on
      // a Wi-Fi-only setting.
      final network = ActiveNetwork.fromConnectivity([ConnectivityResult.vpn]);
      expect(network, ActiveNetwork.other);
      expect(network.isMetered, isFalse);
    });
  });

  group('CellularUsage', () {
    test('accumulates only forward deltas', () {
      final usage = CellularUsage(bytesSent: 100, periodStart: _january);
      expect(usage.plus(50).bytesSent, 150);
      expect(usage.plus(0).bytesSent, 100);
      expect(usage.plus(-20).bytesSent, 100);
    });

    test('rolls over into a new calendar month', () {
      final usage = CellularUsage(bytesSent: 5000, periodStart: _january);

      final rolled = usage.rolledOver(DateTime(2026, 2, 3));

      expect(rolled.bytesSent, 0);
      expect(rolled.periodStart, DateTime(2026, 2));
    });

    test('keeps the total within the same month', () {
      final usage = CellularUsage(bytesSent: 5000, periodStart: _january);

      expect(usage.rolledOver(DateTime(2026, 1, 28)).bytesSent, 5000);
    });

    test('fractionOfCap is null without a cap and can exceed one', () {
      final usage = CellularUsage(bytesSent: 2 * 1024 * 1024 * 1024, periodStart: _january);

      expect(usage.fractionOfCap(null), isNull);
      expect(usage.fractionOfCap(0), isNull);
      expect(usage.fractionOfCap(1000)!, greaterThan(1));
    });
  });

  group('NetworkSettings', () {
    test('survives a JSON round trip, including a null cap', () {
      const withCap = NetworkSettings(
        preferredNetwork: PreferredNetwork.wifiOnly,
        cellularDataCapMb: 5000,
        warnBeforeCap: false,
      );
      expect(NetworkSettings.fromJson(withCap.toJson()), withCap);

      const noCap = NetworkSettings(
        preferredNetwork: PreferredNetwork.cellularAllowed,
        cellularDataCapMb: null,
        warnBeforeCap: true,
      );
      expect(NetworkSettings.fromJson(noCap.toJson()), noCap);
    });

    test('copyWith can clear the cap, which a plain null cannot express', () {
      const settings = NetworkSettings(
        preferredNetwork: PreferredNetwork.auto,
        cellularDataCapMb: 2000,
        warnBeforeCap: true,
      );

      expect(settings.copyWith(cellularDataCapMb: null).cellularDataCapMb, 2000);
      expect(settings.copyWith(clearCap: true).cellularDataCapMb, isNull);
    });
  });

  group('providers', () {
    ProviderContainer buildContainer() {
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('settings changes persist for the next session', () async {
      final container = buildContainer();
      await container
          .read(networkSettingsProvider.notifier)
          .setPreferredNetwork(PreferredNetwork.wifiOnly);
      await container.read(networkSettingsProvider.notifier).setCellularDataCapMb(1000);

      final reopened = buildContainer();
      expect(reopened.read(networkSettingsProvider).preferredNetwork, PreferredNetwork.wifiOnly);
      expect(reopened.read(networkSettingsProvider).cellularDataCapMb, 1000);
    });

    test('clearing the cap persists as cleared', () async {
      final container = buildContainer();
      await container.read(networkSettingsProvider.notifier).setCellularDataCapMb(1000);
      await container.read(networkSettingsProvider.notifier).setCellularDataCapMb(null);

      expect(buildContainer().read(networkSettingsProvider).cellularDataCapMb, isNull);
    });

    test('usage accumulates and resets', () async {
      final container = buildContainer();
      await container.read(cellularUsageProvider.notifier).add(1024);
      await container.read(cellularUsageProvider.notifier).add(1024);

      expect(container.read(cellularUsageProvider).bytesSent, 2048);

      await container.read(cellularUsageProvider.notifier).reset();
      expect(container.read(cellularUsageProvider).bytesSent, 0);
    });

    test('usage survives a restart', () async {
      await addUsageThenClose(4096);

      final reopened = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
      );
      addTearDown(reopened.dispose);

      expect(reopened.read(cellularUsageProvider).bytesSent, 4096);
    });

    test('a stored total from a previous month reads as zero', () async {
      await NetworkSettingsRepository(settings).writeUsage(
        CellularUsage(bytesSent: 9999, periodStart: DateTime(2020, 5)),
      );

      expect(buildContainer().read(cellularUsageProvider).bytesSent, 0);
    });
  });
}

