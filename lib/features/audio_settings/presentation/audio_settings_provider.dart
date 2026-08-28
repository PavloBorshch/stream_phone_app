import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/settings_repository_provider.dart';
import '../data/audio_settings_repository.dart';
import '../domain/audio_settings.dart';

final audioSettingsRepositoryProvider = Provider<AudioSettingsRepository>((ref) {
  return AudioSettingsRepository(ref.watch(settingsRepositoryProvider));
});

class AudioSettingsNotifier extends Notifier<AudioSettings> {
  @override
  AudioSettings build() {
    return ref.watch(audioSettingsRepositoryProvider).read();
  }

  Future<void> _update(AudioSettings next) async {
    if (next == state) return;
    state = next;
    await ref.read(audioSettingsRepositoryProvider).write(next);
  }

  Future<void> setMicSource(MicSource value) => _update(state.copyWith(micSource: value));

  Future<void> setSampleRate(AudioSampleRate value) => _update(state.copyWith(sampleRate: value));

  Future<void> setBitrateKbps(int value) => _update(state.copyWith(bitrateKbps: value));

  Future<void> setChannels(AudioChannels value) => _update(state.copyWith(channels: value));

  Future<void> setHeadphoneMonitoring(bool value) =>
      _update(state.copyWith(headphoneMonitoring: value));
}

final audioSettingsProvider = NotifierProvider<AudioSettingsNotifier, AudioSettings>(
  AudioSettingsNotifier.new,
);
