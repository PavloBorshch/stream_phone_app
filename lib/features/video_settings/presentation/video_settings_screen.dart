import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../destinations/domain/stream_destination.dart';
import '../../destinations/presentation/destinations_provider.dart';
import '../../settings/presentation/widgets/settings_option_tile.dart';
import '../../streaming_engine/presentation/publisher_provider.dart';
import '../domain/video_overrides.dart';
import '../domain/video_settings.dart';
import 'video_settings_provider.dart';
import 'widgets/bitrate_field.dart';
import 'widgets/destination_overrides_sheet.dart';

class VideoSettingsScreen extends ConsumerWidget {
  const VideoSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(videoSettingsProvider);
    final notifier = ref.read(videoSettingsProvider.notifier);
    final supportedCodecs = ref.watch(supportedVideoCodecsProvider);
    final destinations = ref.watch(destinationsProvider);

    // While the capability query is still in flight nothing is marked
    // unavailable — briefly showing an option that turns out to be
    // unsupported is better than briefly greying out one that is.
    final unavailableCodecs = supportedCodecs.maybeWhen(
      data: (codecs) => VideoCodec.values.where((codec) => !codecs.contains(codec)).toSet(),
      orElse: () => <VideoCodec>{},
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Video')),
      body: ListView(
        children: [
          const SettingsSectionHeader(
            title: 'Encoding',
            subtitle: 'Applies to every destination unless overridden below.',
          ),
          SettingsOptionTile<VideoResolution>(
            title: 'Resolution',
            value: settings.resolution,
            options: VideoResolution.values,
            labelBuilder: (option) => option.displayName,
            onChanged: notifier.setResolution,
          ),
          SettingsOptionTile<VideoFrameRate>(
            title: 'Frame rate',
            value: settings.frameRate,
            options: VideoFrameRate.values,
            labelBuilder: (option) => option.displayName,
            onChanged: notifier.setFrameRate,
          ),
          SettingsOptionTile<VideoCodec>(
            title: 'Codec',
            subtitle: settings.codec.description,
            value: settings.codec,
            options: VideoCodec.values,
            unavailable: unavailableCodecs,
            unavailableNote: 'no hardware encoder',
            labelBuilder: (option) => option.displayName,
            onChanged: notifier.setCodec,
          ),
          _BitrateTile(settings: settings, notifier: notifier),
          const SettingsSectionHeader(
            title: 'Per-destination overrides',
            subtitle: 'A destination with no override follows the settings above, '
                'including later changes to them.',
          ),
          destinations.when(
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No destinations yet. Add one under Destinations & Accounts.',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  )
                : Column(
                    children: [
                      for (final destination in items)
                        _DestinationOverrideTile(destination: destination, base: settings),
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Could not load destinations: $error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _BitrateTile extends StatelessWidget {
  const _BitrateTile({required this.settings, required this.notifier});

  final VideoSettings settings;
  final VideoSettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final recommended = VideoSettings.recommendedBitrateKbps(
      settings.resolution,
      settings.frameRate,
    );
    final isRecommended = settings.bitrateKbps == recommended;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Bitrate', style: TextStyle(color: Colors.white)),
              BitrateField(value: settings.bitrateKbps, onChanged: notifier.setBitrateKbps),
            ],
          ),
          Slider(
            value: settings.bitrateKbps
                .clamp(VideoSettings.minBitrateKbps, VideoSettings.maxBitrateKbps)
                .toDouble(),
            min: VideoSettings.minBitrateKbps.toDouble(),
            max: VideoSettings.maxBitrateKbps.toDouble(),
            divisions: (VideoSettings.maxBitrateKbps - VideoSettings.minBitrateKbps) ~/ 250,
            label: '${settings.bitrateKbps} kbps',
            onChanged: (value) => notifier.setBitrateKbps(value.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isRecommended
                      ? 'Recommended for ${settings.resolution.displayName} '
                          'at ${settings.frameRate.displayName}'
                      : 'Recommended: $recommended kbps',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              if (!isRecommended)
                TextButton(
                  onPressed: notifier.resetBitrateToRecommended,
                  child: const Text('Reset'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DestinationOverrideTile extends ConsumerWidget {
  const _DestinationOverrideTile({required this.destination, required this.base});

  final StreamDestination destination;
  final VideoSettings base;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effective = destination.overrides.applyTo(base);
    final hasOverrides = !destination.overrides.isEmpty;

    return ListTile(
      title: Text(destination.displayName, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        '${effective.resolution.displayName} / ${effective.frameRate.displayName} / '
        '${effective.bitrateKbps} kbps${hasOverrides ? '' : ' (inherited)'}',
        style: TextStyle(
          color: hasOverrides ? Colors.redAccent : Colors.white54,
          fontSize: 12,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: () async {
        final result = await showModalBottomSheet<VideoOverrides>(
          context: context,
          backgroundColor: const Color(0xFF161616),
          isScrollControlled: true,
          builder: (sheetContext) => DestinationOverridesSheet(
            destinationName: destination.displayName,
            base: base,
            overrides: destination.overrides,
          ),
        );
        if (result != null) {
          await ref.read(destinationsProvider.notifier).setOverrides(destination.id, result);
        }
      },
    );
  }
}
