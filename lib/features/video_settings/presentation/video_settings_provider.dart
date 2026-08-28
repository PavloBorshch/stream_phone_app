import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/settings_repository_provider.dart';
import '../data/video_settings_repository.dart';
import '../domain/video_settings.dart';

final videoSettingsRepositoryProvider = Provider<VideoSettingsRepository>((ref) {
  return VideoSettingsRepository(ref.watch(settingsRepositoryProvider));
});

class VideoSettingsNotifier extends Notifier<VideoSettings> {
  @override
  VideoSettings build() {
    return ref.watch(videoSettingsRepositoryProvider).read();
  }

  Future<void> _update(VideoSettings next) async {
    if (next == state) return;
    state = next;
    await ref.read(videoSettingsRepositoryProvider).write(next);
  }

  /// Changing resolution re-targets the bitrate too, but only while the user
  /// hasn't dialled in a number of their own: once [bitrateKbps] differs from
  /// the recommendation for the previous resolution it is treated as a
  /// deliberate choice and left alone, so switching 1080p→720p doesn't
  /// silently discard a custom cap the ingest requires.
  Future<void> setResolution(VideoResolution value) async {
    final wasRecommended =
        state.bitrateKbps == VideoSettings.recommendedBitrateKbps(state.resolution, state.frameRate);
    await _update(
      state.copyWith(
        resolution: value,
        bitrateKbps: wasRecommended
            ? VideoSettings.recommendedBitrateKbps(value, state.frameRate)
            : null,
      ),
    );
  }

  Future<void> setFrameRate(VideoFrameRate value) async {
    final wasRecommended =
        state.bitrateKbps == VideoSettings.recommendedBitrateKbps(state.resolution, state.frameRate);
    await _update(
      state.copyWith(
        frameRate: value,
        bitrateKbps: wasRecommended
            ? VideoSettings.recommendedBitrateKbps(state.resolution, value)
            : null,
      ),
    );
  }

  Future<void> setCodec(VideoCodec value) => _update(state.copyWith(codec: value));

  Future<void> setAdaptiveBitrate(bool value) =>
      _update(state.copyWith(adaptiveBitrate: value));

  Future<void> setBitrateKbps(int value) {
    final clamped = value.clamp(VideoSettings.minBitrateKbps, VideoSettings.maxBitrateKbps);
    return _update(state.copyWith(bitrateKbps: clamped));
  }

  Future<void> resetBitrateToRecommended() {
    return _update(
      state.copyWith(
        bitrateKbps: VideoSettings.recommendedBitrateKbps(state.resolution, state.frameRate),
      ),
    );
  }
}

final videoSettingsProvider = NotifierProvider<VideoSettingsNotifier, VideoSettings>(
  VideoSettingsNotifier.new,
);
