import '../../features/capture/domain/capture_mode.dart';
import '../../features/pc_connection/domain/pc_connection_status.dart';
import '../../features/screencast/domain/screencast_status.dart';
import '../../features/streaming_engine/domain/publisher_event.dart';

/// The cross-cutting session state shared by the capture screen and the
/// settings screen: which capture source is selected, its live status, the
/// status of the (optional, Phase 4+) connection to a paired PC, and the
/// state of the publishing session feeding the configured destinations.
class StreamSessionState {
  const StreamSessionState({
    required this.mode,
    required this.screencastEvent,
    required this.pcConnectionEvent,
    required this.publisherEvent,
    required this.isMuted,
    this.pendingScreencastPublish = false,
    this.networkWarning,
  });

  final CaptureMode mode;
  final ScreencastEvent screencastEvent;
  final PcConnectionEvent pcConnectionEvent;
  final PublisherEvent publisherEvent;

  /// Mic mute is session state rather than an audio *setting*: it is a
  /// transient in-stream action (Phase 7's quick mute toggle) that must not
  /// survive into the next session the way `AudioSettings` does.
  final bool isMuted;

  /// Set while a screencast the user started *in order to stream* is still
  /// coming up. Publishing can only begin once the native capture reaches
  /// `capturing`, so the intent has to be remembered across that gap — it is
  /// what distinguishes "user tapped record" from a screencast that was
  /// already running when the app reopened, which must not start publishing
  /// on its own.
  final bool pendingScreencastPublish;

  /// A network condition worth telling the user about that is *not* a failure
  /// — passing the mobile-data cap, say. Kept separate from
  /// `publisherEvent.message` so a warning can never be mistaken for the
  /// reason a stream stopped.
  final String? networkWarning;

  static const initial = StreamSessionState(
    mode: CaptureMode.camera,
    screencastEvent: ScreencastEvent.idle,
    pcConnectionEvent: PcConnectionEvent.idle,
    publisherEvent: PublisherEvent.idle,
    isMuted: false,
  );

  /// True while the app is publishing (or trying to) — the record button
  /// shows "stop" and the status pill switches to live stats.
  bool get isStreaming => publisherEvent.isActive;

  StreamSessionState copyWith({
    CaptureMode? mode,
    ScreencastEvent? screencastEvent,
    PcConnectionEvent? pcConnectionEvent,
    PublisherEvent? publisherEvent,
    bool? isMuted,
    bool? pendingScreencastPublish,
    String? networkWarning,
    bool clearNetworkWarning = false,
  }) {
    return StreamSessionState(
      mode: mode ?? this.mode,
      screencastEvent: screencastEvent ?? this.screencastEvent,
      pcConnectionEvent: pcConnectionEvent ?? this.pcConnectionEvent,
      publisherEvent: publisherEvent ?? this.publisherEvent,
      isMuted: isMuted ?? this.isMuted,
      pendingScreencastPublish: pendingScreencastPublish ?? this.pendingScreencastPublish,
      networkWarning: clearNetworkWarning ? null : (networkWarning ?? this.networkWarning),
    );
  }
}
