/// Output resolutions offered by the Video Settings screen. Values are the
/// encoder's *landscape* frame size; the capture layer swaps them for a
/// portrait sensor orientation.
enum VideoResolution {
  p480(854, 480, '480p'),
  p720(1280, 720, '720p (HD)'),
  p1080(1920, 1080, '1080p (Full HD)'),
  p1440(2560, 1440, '1440p (2K)'),
  p2160(3840, 2160, '2160p (4K)');

  const VideoResolution(this.width, this.height, this.displayName);

  final int width;
  final int height;
  final String displayName;

  static VideoResolution fromName(String? name) {
    return VideoResolution.values.firstWhere(
      (value) => value.name == name,
      orElse: () => VideoResolution.p1080,
    );
  }
}

enum VideoFrameRate {
  fps24(24, '24 fps'),
  fps30(30, '30 fps'),
  fps60(60, '60 fps');

  const VideoFrameRate(this.fps, this.displayName);

  final int fps;
  final String displayName;

  static VideoFrameRate fromName(String? name) {
    return VideoFrameRate.values.firstWhere(
      (value) => value.name == name,
      orElse: () => VideoFrameRate.fps30,
    );
  }
}

/// Encoders the app can ask for. Availability is hardware-dependent and must
/// be queried at runtime — [av1] in particular exists only on a handful of
/// recent flagship SoCs (PLAN.md §1.5), so it is a capability-gated stretch
/// goal rather than a baseline option. `PublisherPlatform.supportedCodecs()`
/// reports what this device actually has; [fallback] is what to use when a
/// stored preference is no longer available (e.g. the settings were restored
/// onto a different phone).
enum VideoCodec {
  h264('H.264 / AVC', 'Most compatible — every platform accepts it'),
  hevc('H.265 / HEVC', 'Better quality per bit; not accepted by every RTMP ingest'),
  av1('AV1', 'Best quality per bit; hardware encoders are rare');

  const VideoCodec(this.displayName, this.description);

  final String displayName;
  final String description;

  static const fallback = VideoCodec.h264;

  static VideoCodec fromName(String? name) {
    return VideoCodec.values.firstWhere(
      (value) => value.name == name,
      orElse: () => fallback,
    );
  }
}

/// Bitrate the encoder targets, in kbps. Kept as a plain int (not an enum)
/// because custom RTMP ingests have their own caps the user may need to dial
/// in exactly; [VideoSettings.recommendedBitrateKbps] supplies the sane
/// default for a resolution/frame-rate pair.
class VideoSettings {
  const VideoSettings({
    required this.resolution,
    required this.frameRate,
    required this.codec,
    required this.bitrateKbps,
    required this.adaptiveBitrate,
  });

  final VideoResolution resolution;
  final VideoFrameRate frameRate;
  final VideoCodec codec;
  final int bitrateKbps;

  /// Let the publisher lower the encoder bitrate (and, if that isn't enough,
  /// the frame rate) when the network can't carry [bitrateKbps]. Off means the
  /// configured bitrate is held no matter what, which on a weak uplink shows
  /// up as buffering and dropped frames at the ingest instead of a softer
  /// picture (PLAN.md §3.4).
  final bool adaptiveBitrate;

  static const minBitrateKbps = 500;
  static const maxBitrateKbps = 51000;

  static const defaults = VideoSettings(
    resolution: VideoResolution.p1080,
    frameRate: VideoFrameRate.fps30,
    codec: VideoCodec.fallback,
    bitrateKbps: 4500,
    adaptiveBitrate: true,
  );

  /// Baseline H.264 bitrate for a resolution at 30 fps, scaled for other
  /// frame rates. These match the ranges the major ingests publish; HEVC/AV1
  /// reach the same quality lower, but the conservative H.264 number is used
  /// for all codecs so switching codec never silently degrades an ingest that
  /// was already at its cap.
  static int recommendedBitrateKbps(VideoResolution resolution, VideoFrameRate frameRate) {
    final base = switch (resolution) {
      VideoResolution.p480 => 1500,
      VideoResolution.p720 => 3000,
      VideoResolution.p1080 => 4500,
      VideoResolution.p1440 => 9000,
      VideoResolution.p2160 => 15000,
    };
    final scale = switch (frameRate) {
      VideoFrameRate.fps24 => 0.85,
      VideoFrameRate.fps30 => 1.0,
      VideoFrameRate.fps60 => 1.5,
    };
    return (base * scale).round();
  }

  factory VideoSettings.fromJson(Map<String, dynamic> json) {
    return VideoSettings(
      resolution: VideoResolution.fromName(json['resolution'] as String?),
      frameRate: VideoFrameRate.fromName(json['frameRate'] as String?),
      codec: VideoCodec.fromName(json['codec'] as String?),
      bitrateKbps: json['bitrateKbps'] as int? ?? defaults.bitrateKbps,
      adaptiveBitrate: json['adaptiveBitrate'] as bool? ?? defaults.adaptiveBitrate,
    );
  }

  Map<String, dynamic> toJson() => {
    'resolution': resolution.name,
    'frameRate': frameRate.name,
    'codec': codec.name,
    'bitrateKbps': bitrateKbps,
    'adaptiveBitrate': adaptiveBitrate,
  };

  VideoSettings copyWith({
    VideoResolution? resolution,
    VideoFrameRate? frameRate,
    VideoCodec? codec,
    int? bitrateKbps,
    bool? adaptiveBitrate,
  }) {
    return VideoSettings(
      resolution: resolution ?? this.resolution,
      frameRate: frameRate ?? this.frameRate,
      codec: codec ?? this.codec,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      adaptiveBitrate: adaptiveBitrate ?? this.adaptiveBitrate,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VideoSettings &&
        other.resolution == resolution &&
        other.frameRate == frameRate &&
        other.codec == codec &&
        other.bitrateKbps == bitrateKbps &&
        other.adaptiveBitrate == adaptiveBitrate;
  }

  @override
  int get hashCode => Object.hash(resolution, frameRate, codec, bitrateKbps, adaptiveBitrate);
}
