import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/widgets/settings_option_tile.dart';
import '../domain/audio_settings.dart';
import 'audio_settings_provider.dart';

class AudioSettingsScreen extends ConsumerWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(audioSettingsProvider);
    final notifier = ref.read(audioSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Audio')),
      body: ListView(
        children: [
          const SettingsSectionHeader(title: 'Input'),
          SettingsOptionTile<MicSource>(
            title: 'Microphone',
            subtitle: settings.micSource.description,
            value: settings.micSource,
            options: MicSource.values,
            labelBuilder: (option) => option.displayName,
            onChanged: notifier.setMicSource,
          ),
          const SettingsSectionHeader(title: 'Encoding'),
          SettingsOptionTile<AudioSampleRate>(
            title: 'Sample rate',
            value: settings.sampleRate,
            options: AudioSampleRate.values,
            labelBuilder: (option) => option.displayName,
            onChanged: notifier.setSampleRate,
          ),
          SettingsOptionTile<int>(
            title: 'Bitrate',
            value: settings.bitrateKbps,
            options: AudioSettings.bitrateOptionsKbps,
            labelBuilder: (option) => '$option kbps',
            onChanged: notifier.setBitrateKbps,
          ),
          SettingsOptionTile<AudioChannels>(
            title: 'Channels',
            value: settings.channels,
            options: AudioChannels.values,
            labelBuilder: (option) => option.displayName,
            onChanged: notifier.setChannels,
          ),
          const SettingsSectionHeader(title: 'Monitoring'),
          SwitchListTile(
            value: settings.headphoneMonitoring,
            onChanged: notifier.setHeadphoneMonitoring,
            title: const Text('Headphone monitoring', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Hear your own mic through connected headphones. Has no effect '
              'without headphones, since routing it to the speaker would feed '
              'back into the mic.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
