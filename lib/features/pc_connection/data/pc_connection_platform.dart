import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
// Not re-exported by the flutter_webrtc.dart barrel file; imported directly
// for RTCPeerConnectionNative.peerConnectionId (see the getter below), which
// only exists because of the local patch in third_party/flutter_webrtc.
// ignore: implementation_imports
import 'package:flutter_webrtc/src/native/rtc_peerconnection_impl.dart';

import '../domain/pairing_session.dart';
import '../domain/pc_connection_status.dart';
import 'pc_signaling_client.dart';

/// Owns one WebRTC connection to a paired PC, signaled over the PC's local
/// WebSocket server (see HELP.md). Per PLAN.md's Phase 4 scope: LAN-only
/// (empty `iceServers` — host candidates only, no STUN/TURN), and carries
/// exactly one `RTCDataChannel` named `"control"` with no defined payload
/// yet (reserved for Phase 5+ mute/stats) — no camera video track in this
/// phase, to avoid contending with `CameraController`.
///
/// [candidate] must use [PairingAuthMethod.token] — this class is for
/// connecting to an already-paired PC (see `StreamSessionNotifier
/// .connectToPc`), not for the first-time pairing handshake, which the
/// pairing screens perform via [PcSignalingClient.pairOnce] instead.
class PcConnectionPlatform {
  PcConnectionPlatform(this.candidate) : assert(candidate.authMethod == PairingAuthMethod.token);

  final PairingCandidate candidate;

  static const _keepAliveInterval = Duration(seconds: 15);
  static const _handshakeTimeout = Duration(seconds: 10);
  static const _reconnectDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 16),
  ];

  final _eventsController = StreamController<PcConnectionEvent>.broadcast();
  PcSignalingClient? _signaling;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _controlChannel;
  StreamSubscription<Map<String, dynamic>>? _messagesSubscription;
  Timer? _keepAliveTimer;
  int _reconnectAttempt = 0;
  bool _closing = false;

  Stream<PcConnectionEvent> events() => _eventsController.stream;

  /// The native id of the current `RTCPeerConnection`, once negotiating has
  /// started — `null` before that or once torn down. PLAN.md's Leg A (video
  /// to the paired PC) uses this to tell native code which peer connection
  /// to attach a track to; see `third_party/flutter_webrtc/PATCH_NOTES.md`
  /// for why exposing this needed a local patch.
  String? get peerConnectionId => (_peerConnection as RTCPeerConnectionNative?)?.peerConnectionId;

  Future<void> connect() async {
    _closing = false;
    _reconnectAttempt = 0;
    await _connectOnce();
  }

  Future<void> disconnect() async {
    _closing = true;
    await _teardown();
    _emit(PcConnectionPhase.disconnected);
  }

  Future<void> _connectOnce() async {
    _emit(PcConnectionPhase.connectingSignaling);
    final signaling = PcSignalingClient(candidate);
    _signaling = signaling;

    try {
      await signaling.connect();
    } catch (e) {
      _emit(PcConnectionPhase.error, message: 'Signaling connection failed: $e');
      _scheduleReconnect();
      return;
    }

    _messagesSubscription = signaling.messages.listen(_handleMessage, onDone: _handleSignalingDone);

    _emit(PcConnectionPhase.pairing);
    final PairingResult ack;
    try {
      final ackFuture = signaling.messages.firstWhere((m) => m['type'] == 'hello_ack');
      signaling.sendHello();
      final raw = await ackFuture.timeout(_handshakeTimeout);
      if (raw['ok'] != true) {
        throw PairingRejectedException(raw['error'] as String? ?? 'unknown');
      }
      ack = PairingResult(
        pcId: raw['pcId'] as String,
        pcName: raw['pcName'] as String,
        token: raw['token'] as String,
        host: signaling.connectedHost!,
      );
    } catch (e) {
      _emit(PcConnectionPhase.error, message: 'Pairing handshake failed: $e');
      _scheduleReconnect();
      return;
    }

    _emit(PcConnectionPhase.negotiating, pcId: ack.pcId, pcName: ack.pcName);

    final peerConnection = await createPeerConnection({'iceServers': <Map<String, dynamic>>[]});
    _peerConnection = peerConnection;

    peerConnection.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      signaling.send({
        'type': 'ice_candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    peerConnection.onConnectionState = (state) => _handleConnectionState(state, ack.pcId, ack.pcName);

    _controlChannel = await peerConnection.createDataChannel('control', RTCDataChannelInit());

    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);
    signaling.send({'type': 'offer', 'sdp': offer.sdp});

    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) => signaling.send({'type': 'ping'}));
  }

  void _handleMessage(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'answer':
        _peerConnection?.setRemoteDescription(RTCSessionDescription(message['sdp'] as String, 'answer'));
      case 'ice_candidate':
        _peerConnection?.addCandidate(
          RTCIceCandidate(
            message['candidate'] as String?,
            message['sdpMid'] as String?,
            message['sdpMLineIndex'] as int?,
          ),
        );
      case 'bye':
        _scheduleReconnect();
      case 'pong':
      case 'hello_ack':
        break;
    }
  }

  void _handleConnectionState(RTCPeerConnectionState state, String pcId, String pcName) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _reconnectAttempt = 0;
        _emit(PcConnectionPhase.connected, pcId: pcId, pcName: pcName);
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        if (!_closing) _scheduleReconnect(pcId: pcId, pcName: pcName);
      default:
        break;
    }
  }

  void _handleSignalingDone() {
    if (!_closing) _scheduleReconnect();
  }

  /// On WS drop or a failed peer connection, rebuilds a fresh
  /// `RTCPeerConnection` + offer rather than attempting an in-place ICE
  /// restart (deferred per PLAN.md — see HELP.md's reconnect section).
  /// Bounded backoff, then surfaces `disconnected` for a manual retry.
  void _scheduleReconnect({String? pcId, String? pcName}) {
    if (_closing) return;
    unawaited(_teardownPeerOnly());

    if (_reconnectAttempt >= _reconnectDelays.length) {
      _emit(PcConnectionPhase.disconnected, pcId: pcId, pcName: pcName);
      return;
    }
    final delay = _reconnectDelays[_reconnectAttempt];
    _reconnectAttempt++;
    _emit(PcConnectionPhase.reconnecting, pcId: pcId, pcName: pcName, message: 'Retrying in ${delay.inSeconds}s');
    Timer(delay, () {
      if (!_closing) _connectOnce();
    });
  }

  Future<void> _teardownPeerOnly() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    await _messagesSubscription?.cancel();
    _messagesSubscription = null;
    await _controlChannel?.close();
    _controlChannel = null;
    await _peerConnection?.close();
    _peerConnection = null;
    await _signaling?.close();
    _signaling = null;
  }

  Future<void> _teardown() async {
    await _teardownPeerOnly();
  }

  void _emit(PcConnectionPhase phase, {String? pcId, String? pcName, String? message}) {
    if (_eventsController.isClosed) return;
    _eventsController.add(PcConnectionEvent(phase: phase, pcId: pcId, pcName: pcName, message: message));
  }

  Future<void> dispose() async {
    _closing = true;
    await _teardown();
    await _eventsController.close();
  }
}
