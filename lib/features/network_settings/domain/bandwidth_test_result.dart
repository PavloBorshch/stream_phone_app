import '../../video_settings/domain/video_settings.dart';

/// Outcome of a pre-flight upload test (PLAN.md Phase 6).
///
/// The test measures the real path — the user's own ingest, over their current
/// uplink — by publishing to it briefly, so [achievedKbps] is what the link
/// actually sustained rather than an estimate from a generic speed test.
class BandwidthTestResult {
  const BandwidthTestResult({
    required this.achievedKbps,
    required this.targetKbps,
    required this.recommended,
  });

  final int achievedKbps;

  /// What the encoder was asked for during the test, so the UI can say
  /// "47% of target" rather than only an absolute number.
  final int targetKbps;

  /// The highest settings this link looks able to hold, or `null` when even
  /// the smallest preset doesn't fit.
  final VideoSettings? recommended;

  double get fractionOfTarget => targetKbps <= 0 ? 0 : achievedKbps / targetKbps;

  /// True when the link comfortably carried what was asked of it, so there is
  /// nothing to recommend changing.
  bool get meetsTarget => fractionOfTarget >= 0.9;

  /// Headroom kept back from the measured throughput. A link measured at
  /// exactly N kbps cannot reliably *carry* N kbps — bitrate is an average and
  /// real streams are bursty around keyframes — so the recommendation is made
  /// against a deliberately conservative fraction of what was measured.
  static const safetyFactor = 0.8;

  int get usableKbps => (achievedKbps * safetyFactor).round();

  /// Picks the best preset that fits inside [usableKbps], preferring a higher
  /// resolution over a higher frame rate: on a constrained uplink, detail
  /// survives scaling down worse than motion does.
  static BandwidthTestResult evaluate({
    required int achievedKbps,
    required int targetKbps,
    required VideoSettings current,
  }) {
    final usable = (achievedKbps * safetyFactor).round();

    VideoSettings? best;
    for (final resolution in VideoResolution.values) {
      for (final frameRate in VideoFrameRate.values) {
        final needed = VideoSettings.recommendedBitrateKbps(resolution, frameRate);
        if (needed > usable) continue;
        if (best == null ||
            resolution.width > best.resolution.width ||
            (resolution == best.resolution && frameRate.fps > best.frameRate.fps)) {
          best = current.copyWith(
            resolution: resolution,
            frameRate: frameRate,
            bitrateKbps: needed,
          );
        }
      }
    }

    return BandwidthTestResult(
      achievedKbps: achievedKbps,
      targetKbps: targetKbps,
      recommended: best,
    );
  }
}
