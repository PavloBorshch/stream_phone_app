import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository_provider.dart';
import 'package:stream_phone_cam/features/video_settings/domain/video_settings.dart';
import 'package:stream_phone_cam/features/video_settings/presentation/video_settings_provider.dart';

void main() {
  late SettingsRepository settings;

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsRepository.create();
  });

  test('changing resolution re-targets a bitrate the user had not customised', () async {
    final container = buildContainer();
    final notifier = container.read(videoSettingsProvider.notifier);
    expect(
      container.read(videoSettingsProvider).bitrateKbps,
      VideoSettings.recommendedBitrateKbps(VideoResolution.p1080, VideoFrameRate.fps30),
    );

    await notifier.setResolution(VideoResolution.p720);

    expect(
      container.read(videoSettingsProvider).bitrateKbps,
      VideoSettings.recommendedBitrateKbps(VideoResolution.p720, VideoFrameRate.fps30),
    );
  });

  test('a hand-picked bitrate survives a resolution change', () async {
    final container = buildContainer();
    final notifier = container.read(videoSettingsProvider.notifier);

    await notifier.setBitrateKbps(3300);
    await notifier.setResolution(VideoResolution.p720);

    expect(container.read(videoSettingsProvider).bitrateKbps, 3300);
  });

  test('bitrate is clamped to the supported range', () async {
    final container = buildContainer();
    final notifier = container.read(videoSettingsProvider.notifier);

    await notifier.setBitrateKbps(10);
    expect(container.read(videoSettingsProvider).bitrateKbps, VideoSettings.minBitrateKbps);

    await notifier.setBitrateKbps(999999);
    expect(container.read(videoSettingsProvider).bitrateKbps, VideoSettings.maxBitrateKbps);
  });

  test('changes are persisted for the next session', () async {
    final container = buildContainer();
    await container.read(videoSettingsProvider.notifier).setCodec(VideoCodec.hevc);

    // A fresh container reads through the same SettingsRepository, standing in
    // for the next app launch.
    final reopened = buildContainer();
    expect(reopened.read(videoSettingsProvider).codec, VideoCodec.hevc);
  });
}
