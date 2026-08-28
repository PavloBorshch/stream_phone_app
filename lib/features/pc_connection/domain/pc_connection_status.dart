enum PcConnectionPhase {
  idle,
  connectingSignaling,
  pairing,
  negotiating,
  connected,
  reconnecting,
  error,
  disconnected,
}

PcConnectionPhase _phaseFromString(String? value) {
  switch (value) {
    case 'connectingSignaling':
      return PcConnectionPhase.connectingSignaling;
    case 'pairing':
      return PcConnectionPhase.pairing;
    case 'negotiating':
      return PcConnectionPhase.negotiating;
    case 'connected':
      return PcConnectionPhase.connected;
    case 'reconnecting':
      return PcConnectionPhase.reconnecting;
    case 'error':
      return PcConnectionPhase.error;
    case 'disconnected':
      return PcConnectionPhase.disconnected;
    case 'idle':
    default:
      return PcConnectionPhase.idle;
  }
}

/// Live status of the app's WebRTC connection to a paired PC — surfaced via
/// [StreamSessionState.pcConnectionEvent], same role
/// `ScreencastEvent` plays for screencast capture.
class PcConnectionEvent {
  const PcConnectionEvent({required this.phase, this.pcId, this.pcName, this.message});

  final PcConnectionPhase phase;
  final String? pcId;
  final String? pcName;
  final String? message;

  static const idle = PcConnectionEvent(phase: PcConnectionPhase.idle);

  factory PcConnectionEvent.fromMap(Map<String, dynamic> map) {
    return PcConnectionEvent(
      phase: _phaseFromString(map['phase'] as String?),
      pcId: map['pcId'] as String?,
      pcName: map['pcName'] as String?,
      message: map['message'] as String?,
    );
  }
}
