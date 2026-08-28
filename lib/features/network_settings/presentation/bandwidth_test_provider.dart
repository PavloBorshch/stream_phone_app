import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio_settings/presentation/audio_settings_provider.dart';
import '../../destinations/domain/stream_destination.dart';
import '../../destinations/presentation/destinations_provider.dart';
import '../../streaming_engine/presentation/publisher_provider.dart';
import '../../video_settings/presentation/video_settings_provider.dart';
import '../data/bandwidth_test.dart';
import '../domain/bandwidth_test_result.dart';

final bandwidthTestProvider = Provider<BandwidthTest>((ref) {
  return BandwidthTest(ref.watch(publisherPlatformProvider));
});

/// Drives one pre-flight upload test. Holds `null` data before the first run,
/// so the UI can tell "not tested yet" apart from "tested, here's the result".
class BandwidthTestController extends AsyncNotifier<BandwidthTestResult?> {
  @override
  Future<BandwidthTestResult?> build() async => null;

  /// The destination the test would publish to: the first enabled one, since
  /// the UI has to name it in the confirmation prompt *before* anything runs.
  StreamDestination? targetDestination() {
    final destinations = ref.read(destinationsRepositoryProvider).read();
    for (final destination in destinations) {
      if (destination.enabled) return destination;
    }
    return null;
  }

  Future<void> run() async {
    final destination = targetDestination();
    if (destination == null) {
      state = AsyncError(
        BandwidthTestException(
          'No enabled destination to test against. Add one under '
          'Settings > Destinations & Accounts.',
        ),
        StackTrace.current,
      );
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(destinationsRepositoryProvider);
      final streamKey = await repository.readStreamKey(destination.secureKeyId);
      if (streamKey == null || streamKey.isEmpty) {
        throw BandwidthTestException(
          'The stream key for ${destination.displayName} is missing. Re-enter '
          'it under Settings > Destinations & Accounts.',
        );
      }

      return ref.read(bandwidthTestProvider).run(
            destination: destination,
            streamKey: streamKey,
            video: ref.read(videoSettingsProvider),
            audio: ref.read(audioSettingsProvider),
          );
    });
  }

  /// Applies a recommendation to the global video settings.
  Future<void> applyRecommendation() async {
    final recommended = state.valueOrNull?.recommended;
    if (recommended == null) return;
    final notifier = ref.read(videoSettingsProvider.notifier);
    await notifier.setResolution(recommended.resolution);
    await notifier.setFrameRate(recommended.frameRate);
    await notifier.setBitrateKbps(recommended.bitrateKbps);
  }
}

final bandwidthTestControllerProvider =
    AsyncNotifierProvider<BandwidthTestController, BandwidthTestResult?>(
  BandwidthTestController.new,
);
