import 'dart:async';

import '../../audio_settings/domain/audio_settings.dart';
import '../../capture/domain/capture_mode.dart';
import '../../destinations/domain/stream_destination.dart';
import '../../streaming_engine/data/publisher_platform.dart';
import '../../streaming_engine/domain/publish_request.dart';
import '../../video_settings/domain/video_settings.dart';
import '../domain/bandwidth_test_result.dart';

class BandwidthTestException implements Exception {
  BandwidthTestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Measures the real uplink by briefly publishing to the user's own ingest.
///
/// This genuinely goes live on their channel for the duration, which is why
/// nothing here runs without an explicit, per-run confirmation from the UI —
/// see `NetworkSettingsScreen`. The trade-off buys the only measurement that
/// reflects the actual path: their encoder, their uplink, their ingest server,
/// rather than a generic speed test against an unrelated host.
class BandwidthTest {
  BandwidthTest(this._publisher, {this.duration = defaultDuration});

  final PublisherPlatform _publisher;

  /// How long to publish for. Long enough to get past connection setup and
  /// the encoder's initial ramp, short enough that a viewer refreshing at the
  /// wrong moment is the worst case. Injectable so tests don't have to spend
  /// it for real.
  final Duration duration;

  static const defaultDuration = Duration(seconds: 8);

  /// Samples discarded from the start of the run. The first seconds cover the
  /// RTMP handshake and the encoder reaching its configured rate, so including
  /// them would understate the link.
  static const warmupSamples = 3;

  Future<BandwidthTestResult> run({
    required StreamDestination destination,
    required String streamKey,
    required VideoSettings video,
    required AudioSettings audio,
  }) async {
    final samples = <int>[];
    final subscription = _publisher.events().listen((event) {
      final measured = event.bitrateKbps;
      if (measured != null && measured > 0) samples.add(measured);
    });

    try {
      await _publisher.start(
        PublishRequest(
          source: CaptureMode.camera,
          // Adaptation is forced off for the run: the point is to find out
          // what the link does with the configured bitrate, and a controller
          // stepping the target down mid-test would measure its own reaction
          // instead of the network.
          video: video.copyWith(adaptiveBitrate: false),
          audio: audio,
          legs: [
            PublishLeg(
              destinationId: destination.id,
              displayName: destination.displayName,
              url: destination.rtmpUrl,
              streamKey: streamKey,
              video: video,
            ),
          ],
          includePcLeg: false,
        ),
      );

      await Future<void>.delayed(duration);
    } finally {
      // Stopping matters more than reporting: an early failure must not leave
      // the user unknowingly broadcasting.
      await subscription.cancel();
      await _publisher.stop();
    }

    final usable = samples.length > warmupSamples ? samples.sublist(warmupSamples) : samples;
    if (usable.isEmpty) {
      throw BandwidthTestException(
        'No data reached ${destination.displayName}. Check the stream key and the connection.',
      );
    }

    return BandwidthTestResult.evaluate(
      achievedKbps: _median(usable),
      targetKbps: video.bitrateKbps,
      current: video,
    );
  }

  /// Median rather than mean: a single stalled or bursty second would drag an
  /// average well away from what the link actually sustains.
  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }
}
