import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/widgets/settings_option_tile.dart';
import '../domain/battery_performance_settings.dart';
import '../domain/device_health.dart';
import 'battery_performance_provider.dart';

class BatteryPerformanceScreen extends ConsumerWidget {
  const BatteryPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(batteryPerformanceProvider);
    final notifier = ref.read(batteryPerformanceProvider.notifier);
    final battery = ref.watch(batteryStatusProvider);
    final thermal = ref.watch(thermalStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Battery & Performance')),
      body: ListView(
        children: [
          const SettingsSectionHeader(title: 'Now'),
          ListTile(
            title: const Text('Battery', style: TextStyle(color: Colors.white)),
            trailing: Text(
              battery.when(
                data: (value) =>
                    '${value.levelPercent}%${value.isOnPower ? ' (charging)' : ''}',
                loading: () => 'Checking…',
                error: (_, _) => 'Unknown',
              ),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          ListTile(
            title: const Text('Temperature', style: TextStyle(color: Colors.white)),
            subtitle: thermal.valueOrNull == ThermalStatus.unknown
                ? const Text(
                    'This device does not report thermal state (needs Android 10+).',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  )
                : null,
            trailing: Text(
              thermal.when(
                data: (value) => value.displayName,
                loading: () => 'Checking…',
                error: (_, _) => 'Unknown',
              ),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          const SettingsSectionHeader(
            title: 'Low battery',
            subtitle: 'Ignored while the phone is charging.',
          ),
          SettingsOptionTile<PerformanceGuard>(
            title: 'When battery is low',
            subtitle: settings.batteryGuard.description,
            value: settings.batteryGuard,
            options: PerformanceGuard.values,
            labelBuilder: (option) => option.displayName,
            onChanged: notifier.setBatteryGuard,
          ),
          if (settings.batteryGuard != PerformanceGuard.off)
            SettingsOptionTile<int>(
              title: 'Low battery is',
              value: settings.batteryThresholdPercent,
              options: BatteryPerformanceSettings.thresholdOptions,
              labelBuilder: (option) => '$option% or less',
              onChanged: notifier.setBatteryThresholdPercent,
            ),
          const SettingsSectionHeader(
            title: 'Overheating',
            subtitle: 'A hot phone throttles its own encoder, so backing off '
                'early keeps the stream smoother than letting frames drop.',
          ),
          SettingsOptionTile<PerformanceGuard>(
            title: 'When the phone is hot',
            subtitle: settings.thermalGuard.description,
            value: settings.thermalGuard,
            options: PerformanceGuard.values,
            labelBuilder: (option) => option.displayName,
            onChanged: notifier.setThermalGuard,
          ),
          const SettingsSectionHeader(title: 'Screen'),
          SwitchListTile(
            value: settings.keepScreenAwake,
            onChanged: notifier.setKeepScreenAwake,
            title: const Text('Keep screen awake', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Streaming continues with the screen off, but the preview is how '
              'you frame the shot.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
