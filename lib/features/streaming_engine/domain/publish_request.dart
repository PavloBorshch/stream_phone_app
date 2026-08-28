import '../../audio_settings/domain/audio_settings.dart';
import '../../capture/domain/capture_mode.dart';
import '../../video_settings/domain/video_settings.dart';

/// One destination leg, already resolved: the global [VideoSettings] merged
/// with that destination's overrides, and the stream key read out of secure
/// storage. Built by `StreamSessionNotifier.startStream()` — the native side
/// never reads settings or secrets itself, it only receives them here.
class PublishLeg {
  const PublishLeg({
    required this.destinationId,
    required this.displayName,
    required this.url,
    required this.streamKey,
    required this.video,
  });

  final String destinationId;
  final String displayName;

  /// Ingest URL as the user entered it (or as OAuth filled it in) —
  /// `rtmp://`, `rtmps://` or `srt://`. The native publisher picks its
  /// protocol implementation from this scheme.
  final String url;
  final String streamKey;

  /// Effective per-leg video settings (global settings with this
  /// destination's overrides applied).
  final VideoSettings video;

  Map<String, dynamic> toMap() => {
    'destinationId': destinationId,
    'displayName': displayName,
    'url': url,
    'streamKey': streamKey,
    'width': video.resolution.width,
    'height': video.resolution.height,
    'fps': video.frameRate.fps,
    'bitrateKbps': video.bitrateKbps,
  };
}

/// The complete description of a publishing session handed to the native
/// encoder/publisher in one `start` call.
///
/// [video] is the *capture* configuration — the size and rate the shared
/// composited frame is produced at. Each leg then runs its own hardware
/// encoder off that shared frame (verified against HaishinKit 0.18.2: every
/// `Stream` lazily owns its own `VideoCodec`), which is exactly what makes
/// per-destination resolution and bitrate overrides real rather than
/// cosmetic. A leg asking for more than the capture size is not rejected, it
/// simply gains no detail beyond what was captured.
class PublishRequest {
  const PublishRequest({
    required this.source,
    required this.video,
    required this.audio,
    required this.legs,
    required this.includePcLeg,
    this.pcPeerConnectionId,
  });

  final CaptureMode source;
  final VideoSettings video;
  final AudioSettings audio;
  final List<PublishLeg> legs;

  /// Whether the paired-PC WebRTC leg (PLAN.md §1.5 "Leg A") should be fed
  /// from the same capture session. Distinct from [legs], which are all
  /// RTMP/RTMPS/SRT ingests ("Leg B") the native publisher dials itself.
  final bool includePcLeg;

  /// The connected PC's `RTCPeerConnection` id (`PcConnectionPlatform
  /// .peerConnectionId`), so native code knows which peer connection to
  /// attach the composited-video track to — see HELP.md §8's "Leg A media
  /// track" section. Only meaningful when [includePcLeg] is true; `null`
  /// means Leg A is skipped even if [includePcLeg] was requested (e.g. the
  /// PC connection dropped between the check and the call).
  final String? pcPeerConnectionId;

  Map<String, dynamic> toMap() => {
    'source': source.name,
    'video': {
      'width': video.resolution.width,
      'height': video.resolution.height,
      'fps': video.frameRate.fps,
      'codec': video.codec.name,
      'bitrateKbps': video.bitrateKbps,
      'adaptive': video.adaptiveBitrate,
    },
    'audio': {
      'micSource': audio.micSource.name,
      'sampleRate': audio.sampleRate.hz,
      'bitrateKbps': audio.bitrateKbps,
      'channels': audio.channels.count,
      'headphoneMonitoring': audio.headphoneMonitoring,
    },
    'legs': legs.map((leg) => leg.toMap()).toList(),
    'includePcLeg': includePcLeg,
    'pcPeerConnectionId': pcPeerConnectionId,
  };
}
