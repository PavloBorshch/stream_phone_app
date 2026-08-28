/// Lifecycle of one publishing session, mirroring `ScreencastStatus`'s shape
/// (PLAN.md's "typed status decoded from a paired EventChannel" pattern).
///
/// [reconnecting] is distinct from [connecting] on purpose: the first means
/// "never been live yet", the second "was live, lost the socket, retrying" —
/// the UI treats the second as still-streaming (the encoder keeps running)
/// and only the first as a startup that can still fail outright.
enum PublisherStatus { idle, connecting, live, reconnecting, stopped, error }

PublisherStatus _statusFromString(String? value) {
  switch (value) {
    case 'connecting':
      return PublisherStatus.connecting;
    case 'live':
      return PublisherStatus.live;
    case 'reconnecting':
      return PublisherStatus.reconnecting;
    case 'stopped':
      return PublisherStatus.stopped;
    case 'error':
      return PublisherStatus.error;
    case 'idle':
    default:
      return PublisherStatus.idle;
  }
}

/// Per-leg state. One of these exists per enabled destination while
/// multistreaming, so a single failing ingest is reported (and can be
/// retried) without collapsing the whole session's status.
class DestinationPublishState {
  const DestinationPublishState({
    required this.destinationId,
    required this.status,
    this.targetBitrateKbps,
    this.droppedFrames,
    this.rttMs,
    this.message,
  });

  final String destinationId;
  final PublisherStatus status;

  /// What this leg's encoder is currently *set* to, which adaptive bitrate may
  /// have stepped below the configured value. Per-leg throughput cannot be
  /// measured on Android — HaishinKit keeps `RtmpStream.connection` internal
  /// to its own module, so its byte counters are out of reach — which is why
  /// only the session-wide [PublisherEvent.bitrateKbps] is a measurement.
  final int? targetBitrateKbps;
  final int? droppedFrames;
  final int? rttMs;
  final String? message;

  factory DestinationPublishState.fromMap(Map<String, dynamic> map) {
    return DestinationPublishState(
      destinationId: map['destinationId'] as String? ?? '',
      status: _statusFromString(map['status'] as String?),
      targetBitrateKbps: map['targetBitrateKbps'] as int?,
      droppedFrames: map['droppedFrames'] as int?,
      rttMs: map['rttMs'] as int?,
      message: map['message'] as String?,
    );
  }
}

/// A snapshot of the whole publishing session: the aggregate [status] the
/// record button reacts to, the live stats the status pill renders, and the
/// per-destination breakdown.
class PublisherEvent {
  const PublisherEvent({
    required this.status,
    this.destinations = const [],
    this.bitrateKbps,
    this.targetBitrateKbps,
    this.bytesSent,
    this.fps,
    this.droppedFrames,
    this.uptimeSeconds,
    this.message,
  });

  final PublisherStatus status;
  final List<DestinationPublishState> destinations;

  /// Measured outgoing rate across all legs, from the platform's own transmit
  /// byte counter — the real number, as opposed to [targetBitrateKbps].
  final int? bitrateKbps;

  /// Sum of what the legs' encoders are configured to produce. Diverging from
  /// [bitrateKbps] is the signal adaptive bitrate acts on, and the pair is
  /// what makes "the network is the bottleneck" visible in the UI.
  final int? targetBitrateKbps;

  /// Bytes transmitted since this session started. Feeds the mobile-data cap
  /// (PLAN.md Phase 6); resets to zero with each new session, so consumers
  /// must accumulate deltas rather than assume it only grows.
  final int? bytesSent;
  final int? fps;
  final int? droppedFrames;
  final int? uptimeSeconds;
  final String? message;

  static const idle = PublisherEvent(status: PublisherStatus.idle);

  /// True while the encoder is running, including during a mid-stream
  /// reconnect — the record button shows "stop" for all of these.
  bool get isActive =>
      status == PublisherStatus.connecting ||
      status == PublisherStatus.live ||
      status == PublisherStatus.reconnecting;

  factory PublisherEvent.fromMap(Map<String, dynamic> map) {
    final rawDestinations = map['destinations'] as List<dynamic>? ?? const [];
    return PublisherEvent(
      status: _statusFromString(map['status'] as String?),
      destinations: rawDestinations
          .map((e) => DestinationPublishState.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      bitrateKbps: map['bitrateKbps'] as int?,
      targetBitrateKbps: map['targetBitrateKbps'] as int?,
      bytesSent: map['bytesSent'] as int?,
      fps: map['fps'] as int?,
      droppedFrames: map['droppedFrames'] as int?,
      uptimeSeconds: map['uptimeSeconds'] as int?,
      message: map['message'] as String?,
    );
  }
}
