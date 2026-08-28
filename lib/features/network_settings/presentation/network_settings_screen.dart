import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/widgets/settings_option_tile.dart';
import '../../video_settings/presentation/video_settings_provider.dart';
import '../data/bandwidth_test.dart';
import '../domain/bandwidth_test_result.dart';
import '../domain/network_settings.dart';
import 'bandwidth_test_provider.dart';
import 'network_settings_provider.dart';

/// Sentinel for the "no cap" entry in the cap dropdown, which otherwise has no
/// value to represent `null`.
const _noCap = -1;

class NetworkSettingsScreen extends ConsumerWidget {
  const NetworkSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(networkSettingsProvider);
    final notifier = ref.read(networkSettingsProvider.notifier);
    final video = ref.watch(videoSettingsProvider);
    final network = ref.watch(activeNetworkProvider);
    final usage = ref.watch(cellularUsageProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Network')),
      body: ListView(
        children: [
          const SettingsSectionHeader(title: 'Connection'),
          ListTile(
            title: const Text('Current connection', style: TextStyle(color: Colors.white)),
            trailing: Text(
              network.when(
                data: (value) => value.displayName,
                loading: () => 'Checking…',
                // A failed connectivity lookup must not read as "offline" —
                // the policy checks treat unknown as "allowed", and the UI
                // should say the same thing.
                error: (_, _) => 'Unknown',
              ),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          SettingsOptionTile<PreferredNetwork>(
            title: 'Allowed networks',
            subtitle: settings.preferredNetwork.description,
            value: settings.preferredNetwork,
            options: PreferredNetwork.values,
            labelBuilder: (option) => option.displayName,
            onChanged: notifier.setPreferredNetwork,
          ),
          const SettingsSectionHeader(
            title: 'Mobile data',
            subtitle: 'Only mobile data counts towards the cap; Wi-Fi and Ethernet are ignored.',
          ),
          SettingsOptionTile<int>(
            title: 'Data cap',
            value: settings.cellularDataCapMb ?? _noCap,
            options: const [_noCap, ...NetworkSettings.capOptionsMb],
            labelBuilder: (option) =>
                option == _noCap ? 'No cap' : '${(option / 1000).toStringAsFixed(option % 1000 == 0 ? 0 : 1)} GB',
            onChanged: (value) => notifier.setCellularDataCapMb(value == _noCap ? null : value),
          ),
          if (settings.cellularDataCapMb != null)
            SwitchListTile(
              value: settings.warnBeforeCap,
              onChanged: notifier.setWarnBeforeCap,
              title: const Text('Warn before the cap', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Warn at 80% as well as at the cap — a stream can spend the '
                'last of an allowance in a few minutes.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          _UsageTile(usageMb: usage.megabytesSent, capMb: settings.cellularDataCapMb),
          const SettingsSectionHeader(
            title: 'Connection test',
            subtitle: 'Measures the real uplink by publishing to your ingest for '
                'a few seconds.',
          ),
          const _BandwidthTestTile(),
          const SettingsSectionHeader(
            title: 'Adaptive quality',
            subtitle: 'Lowers the bitrate, then the frame rate, when the uplink '
                'cannot carry the configured quality.',
          ),
          SwitchListTile(
            value: video.adaptiveBitrate,
            onChanged: ref.read(videoSettingsProvider.notifier).setAdaptiveBitrate,
            title: const Text('Adapt to the connection', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              video.adaptiveBitrate
                  ? 'Quality may drop below ${video.bitrateKbps} kbps to keep the stream up.'
                  : 'Always send ${video.bitrateKbps} kbps, even if the uplink '
                      'cannot carry it.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _UsageTile extends ConsumerWidget {
  const _UsageTile({required this.usageMb, required this.capMb});

  final double usageMb;
  final int? capMb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fraction = capMb == null || capMb! <= 0 ? null : (usageMb / capMb!).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Used this month', style: TextStyle(color: Colors.white)),
              Text(
                capMb == null
                    ? '${usageMb.toStringAsFixed(1)} MB'
                    : '${usageMb.toStringAsFixed(1)} / $capMb MB',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: fraction,
              backgroundColor: Colors.white12,
              color: fraction >= NetworkSettings.warnThresholdFraction
                  ? Colors.redAccent
                  : Colors.white70,
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => ref.read(cellularUsageProvider.notifier).reset(),
              child: const Text('Reset counter'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandwidthTestTile extends ConsumerWidget {
  const _BandwidthTestTile();

  /// The test really does broadcast, so consent is asked for every run and
  /// names the destination it is about to go live on — a one-time preference
  /// would not be informed consent for a later run against a different
  /// channel.
  Future<bool> _confirm(BuildContext context, String destinationName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF212121),
        title: const Text('Go live briefly?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This publishes to $destinationName for '
          '${BandwidthTest.defaultDuration.inSeconds} seconds to measure your upload '
          'speed. Anyone watching that channel may see it.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Run test'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bandwidthTestControllerProvider);
    final controller = ref.read(bandwidthTestControllerProvider.notifier);
    final isRunning = state.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('Test connection', style: TextStyle(color: Colors.white)),
          subtitle: Text(
            isRunning
                ? 'Publishing for ${BandwidthTest.defaultDuration.inSeconds} seconds…'
                : 'Briefly goes live on your first enabled destination.',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: isRunning
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2),
                )
              : FilledButton(
                  onPressed: () async {
                    final destination = controller.targetDestination();
                    if (destination == null) {
                      await controller.run();
                      return;
                    }
                    if (await _confirm(context, destination.displayName)) {
                      await controller.run();
                    }
                  },
                  child: const Text('Run'),
                ),
        ),
        state.when(
          loading: () => const SizedBox.shrink(),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              error is BandwidthTestException ? error.message : '$error',
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
          data: (result) => result == null
              ? const SizedBox.shrink()
              : _ResultCard(result: result, onApply: controller.applyRecommendation),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onApply});

  final BandwidthTestResult result;
  final Future<void> Function() onApply;

  @override
  Widget build(BuildContext context) {
    final recommended = result.recommended;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Achieved ${result.achievedKbps} kbps '
            '(${(result.fractionOfTarget * 100).round()}% of the configured '
            '${result.targetKbps} kbps)',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 4),
          if (result.meetsTarget)
            const Text(
              'Your connection carries the configured quality.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            )
          else if (recommended == null)
            const Text(
              'Too slow for even the lowest preset. Streaming will keep '
              'dropping quality to stay connected.',
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
            )
          else ...[
            Text(
              'Recommended: ${recommended.resolution.displayName} at '
              '${recommended.frameRate.displayName}, '
              '${recommended.bitrateKbps} kbps',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onApply,
                child: const Text('Apply'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
