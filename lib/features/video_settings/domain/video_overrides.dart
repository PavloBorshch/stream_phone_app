import 'video_settings.dart';

/// Per-destination deviations from the global [VideoSettings] (PLAN.md
/// Phase 5). Every field is nullable and `null` means "inherit the global
/// value" — that distinction is the whole point of this type, so a
/// destination that was never customised keeps tracking later changes to the
/// global settings instead of freezing a copy of them.
///
/// Resolution, frame rate and bitrate are overridable because each leg runs
/// its own encoder off the shared captured frame. Codec is deliberately left
/// out even though it technically could vary per leg: mixing codecs across
/// destinations multiplies the ways a stream can be rejected by an ingest for
/// no benefit the user asked for, so it stays a single session-wide choice.
class VideoOverrides {
  const VideoOverrides({this.resolution, this.frameRate, this.bitrateKbps});

  final VideoResolution? resolution;
  final VideoFrameRate? frameRate;
  final int? bitrateKbps;

  static const none = VideoOverrides();

  bool get isEmpty => resolution == null && frameRate == null && bitrateKbps == null;

  /// The effective settings for this destination: [base] with whichever
  /// fields this override actually specifies replaced.
  VideoSettings applyTo(VideoSettings base) {
    return base.copyWith(
      resolution: resolution,
      frameRate: frameRate,
      bitrateKbps: bitrateKbps,
    );
  }

  factory VideoOverrides.fromJson(Map<String, dynamic> json) {
    final resolution = json['resolution'] as String?;
    final frameRate = json['frameRate'] as String?;
    return VideoOverrides(
      resolution: resolution == null ? null : VideoResolution.fromName(resolution),
      frameRate: frameRate == null ? null : VideoFrameRate.fromName(frameRate),
      bitrateKbps: json['bitrateKbps'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (resolution != null) 'resolution': resolution!.name,
    if (frameRate != null) 'frameRate': frameRate!.name,
    if (bitrateKbps != null) 'bitrateKbps': bitrateKbps,
  };

  /// `null` for a field clears that override (back to inheriting the global
  /// value), so this deliberately does *not* use the usual
  /// `value ?? this.value` copyWith idiom — callers pass the complete new
  /// override instead. Provided for the "clear one field" case only.
  VideoOverrides without({bool resolution = false, bool frameRate = false, bool bitrate = false}) {
    return VideoOverrides(
      resolution: resolution ? null : this.resolution,
      frameRate: frameRate ? null : this.frameRate,
      bitrateKbps: bitrate ? null : bitrateKbps,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VideoOverrides &&
        other.resolution == resolution &&
        other.frameRate == frameRate &&
        other.bitrateKbps == bitrateKbps;
  }

  @override
  int get hashCode => Object.hash(resolution, frameRate, bitrateKbps);
}
