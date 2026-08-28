import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository_provider.dart';
import 'package:stream_phone_cam/features/audio_settings/data/audio_settings_repository.dart';
import 'package:stream_phone_cam/features/audio_settings/domain/audio_settings.dart';
import 'package:stream_phone_cam/features/audio_settings/presentation/audio_settings_provider.dart';

void main() {
  late SettingsRepository settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsRepository.create();
  });

  test('survives a JSON round trip', () {
    const audio = AudioSettings(
      micSource: MicSource.wiredHeadset,
      sampleRate: AudioSampleRate.hz44100,
      bitrateKbps: 192,
      channels: AudioChannels.mono,
      headphoneMonitoring: true,
    );

    expect(AudioSettings.fromJson(audio.toJson()), audio);
  });

  test('falls back to defaults for unknown stored values', () {
    final audio = AudioSettings.fromJson({
      'micSource': 'usbInterface',
      'sampleRate': 'hz96000',
      'channels': 'surround',
    });

    expect(audio.micSource, MicSource.automatic);
    expect(audio.sampleRate, AudioSampleRate.hz48000);
    expect(audio.channels, AudioChannels.stereo);
  });

  test('repository reads defaults when nothing is stored', () async {
    expect(AudioSettingsRepository(settings).read(), AudioSettings.defaults);
  });

  test('provider changes are persisted for the next session', () async {
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    await container.read(audioSettingsProvider.notifier).setChannels(AudioChannels.mono);
    await container.read(audioSettingsProvider.notifier).setHeadphoneMonitoring(true);

    final reopened = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
    );
    addTearDown(reopened.dispose);

    expect(reopened.read(audioSettingsProvider).channels, AudioChannels.mono);
    expect(reopened.read(audioSettingsProvider).headphoneMonitoring, isTrue);
  });
}
