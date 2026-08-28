import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/features/video_settings/data/video_settings_repository.dart';
import 'package:stream_phone_cam/features/video_settings/domain/video_overrides.dart';
import 'package:stream_phone_cam/features/video_settings/domain/video_settings.dart';

void main() {
  group('VideoSettings', () {
    test('recommended bitrate scales with resolution and frame rate', () {
      final p1080at30 = VideoSettings.recommendedBitrateKbps(
        VideoResolution.p1080,
        VideoFrameRate.fps30,
      );
      final p1080at60 = VideoSettings.recommendedBitrateKbps(
        VideoResolution.p1080,
        VideoFrameRate.fps60,
      );
      final p720at30 = VideoSettings.recommendedBitrateKbps(
        VideoResolution.p720,
        VideoFrameRate.fps30,
      );

      expect(p1080at60, greaterThan(p1080at30));
      expect(p720at30, lessThan(p1080at30));
    });

    test('survives a JSON round trip', () {
      const settings = VideoSettings(
        resolution: VideoResolution.p1440,
        frameRate: VideoFrameRate.fps60,
        codec: VideoCodec.hevc,
        bitrateKbps: 12000,
        adaptiveBitrate: false,
      );

      expect(VideoSettings.fromJson(settings.toJson()), settings);
    });

    test('falls back to defaults for unknown stored values', () {
      final settings = VideoSettings.fromJson({
        'resolution': 'p4320',
        'frameRate': 'fps120',
        'codec': 'vp9',
      });

      expect(settings.resolution, VideoResolution.p1080);
      expect(settings.frameRate, VideoFrameRate.fps30);
      // A codec the device might not have must never be inferred from junk —
      // an unreadable value has to land on the universally supported one.
      expect(settings.codec, VideoCodec.h264);
    });
  });

  group('VideoOverrides', () {
    test('null fields inherit from the base settings', () {
      const base = VideoSettings.defaults;
      const overrides = VideoOverrides(resolution: VideoResolution.p720);

      final effective = overrides.applyTo(base);

      expect(effective.resolution, VideoResolution.p720);
      expect(effective.frameRate, base.frameRate);
      expect(effective.bitrateKbps, base.bitrateKbps);
      expect(effective.codec, base.codec);
    });

    test('an empty override changes nothing', () {
      expect(VideoOverrides.none.applyTo(VideoSettings.defaults), VideoSettings.defaults);
      expect(VideoOverrides.none.isEmpty, isTrue);
    });

    test('only set fields are serialised, so unset stays unset after a round trip', () {
      const overrides = VideoOverrides(bitrateKbps: 2500);
      final json = overrides.toJson();

      expect(json.containsKey('resolution'), isFalse);
      expect(VideoOverrides.fromJson(json), overrides);
      expect(VideoOverrides.fromJson(json).resolution, isNull);
    });

    test('without() clears a single field back to inherited', () {
      const overrides = VideoOverrides(
        resolution: VideoResolution.p720,
        bitrateKbps: 2500,
      );

      final cleared = overrides.without(bitrate: true);

      expect(cleared.resolution, VideoResolution.p720);
      expect(cleared.bitrateKbps, isNull);
    });
  });

  group('VideoSettingsRepository', () {
    late VideoSettingsRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = VideoSettingsRepository(await SettingsRepository.create());
    });

    test('reads defaults when nothing is stored', () {
      expect(repository.read(), VideoSettings.defaults);
    });

    test('persists and reloads written settings', () async {
      const settings = VideoSettings(
        resolution: VideoResolution.p720,
        frameRate: VideoFrameRate.fps60,
        codec: VideoCodec.h264,
        bitrateKbps: 4500,
        adaptiveBitrate: true,
      );

      await repository.write(settings);

      expect(repository.read(), settings);
    });
  });
}
