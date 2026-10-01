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
/// [candidate] must use [PairingAuthMethod.token] (an already-paired PC —
/// see `StreamSessionNotifier.connectToPc`) or [PairingAuthMethod.usb] (a
/// PC reached over the cable, which needs no prior pairing). Not for the
/// one-shot PIN handshake, which the pairing screens perform via
/// [PcSignalingClient.pairOnce] instead.
class PcConnectionPlatform {
  PcConnectionPlatform(this.candidate)
      : assert(
          candidate.authMethod == PairingAuthMethod.token ||
              candidate.authMethod == PairingAuthMethod.usb,
          'a live session authenticates with a stored token, or with the USB '
          'cable itself -- a PIN is for the one-shot pairing handshake',
        );

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

  /// Guards [onRenegotiationNeeded] below: `createDataChannel` alone can
  /// already set a fresh `RTCPeerConnection`'s negotiation-needed flag, so
  /// the event can fire *before* the explicit initial offer a few lines down
  /// does — without this guard that would race two competing offers for the
  /// same initial handshake. Set once the initial offer is actually sent;
  /// until then, the explicit call below is the only thing allowed to negotiate.
  bool _initialOfferSent = false;

  /// Identifies one `_connectOnce()` attempt — bumped every time a fresh one
  /// starts. Every callback that can trigger a side effect (a reconnect, a
  /// renegotiation offer) captures the generation that was current when it
  /// was registered and checks it's still current before acting.
  ///
  /// Needed because `RTCPeerConnection.close()` (called from
  /// `_teardownPeerOnly`) does not synchronously unregister this instance's
  /// event listeners — closing the *old* peer connection can still fire a
  /// late `onConnectionState` callback (transitioning through
  /// closing/closed) after a *newer* `_connectOnce()` attempt has already
  /// started and overwritten `_peerConnection`/`_signaling`. Without this
  /// guard that stale callback would call `_scheduleReconnect()` again for
  /// an attempt that's already been superseded, and `_teardownPeerOnly()`
  /// would tear down the newer (possibly healthy) attempt instead of the
  /// old one it actually meant to close. Found by code audit while chasing
  /// a real-device report of ~28 stuck half-open PC sessions after an app
  /// restart — see HELP.md §9's "Fixed 2026-08-31" bullet.
  int _connectionGeneration = 0;

  /// Guards against a *different* double-schedule within the same
  /// generation: `_handleConnectionState` (Failed/Disconnected/Closed) and
  /// `_handleSignalingDone` (the message stream's `onDone`) can both fire
  /// for the very same underlying disconnect, before any newer
  /// `_connectOnce()` attempt exists to make `_connectionGeneration` differ.
  /// Reset alongside a fresh generation in `_connectOnce()`; set the first
  /// time `_scheduleReconnect()` actually schedules something for the
  /// current generation, so a second, redundant trigger for the same
  /// failure is a no-op instead of a second competing retry timer.
  bool _reconnectScheduledForGeneration = false;

  Stream<PcConnectionEvent> events() => _eventsController.stream;

  /// The native id of the current `RTCPeerConnection`, once negotiating has
  /// started — `null` before that or once torn down. PLAN.md's Leg A (video
  /// to the paired PC) uses this to tell native code which peer connection
  /// to attach a track to; see `third_party/flutter_webrtc/PATCH_NOTES.md`
  /// for why exposing this needed a local patch.
  String? get peerConnectionId => (_peerConnection as RTCPeerConnectionNative?)?.peerConnectionId;

  /// Which of the candidate's addresses actually answered, once signaling
  /// has connected. `127.0.0.1` means this session is running through the
  /// PC's `adb reverse` USB tunnel rather than over any network -- which
  /// changes how media has to be sent, since WebRTC cannot cross that
  /// tunnel (see `usb_bridge_discovery.dart`).
  String? get connectedHost => _signaling?.connectedHost;

  /// The pairing token the PC issued for this session's `hello_ack`.
  ///
  /// Only interesting for a [PairingAuthMethod.usb] session, where the
  /// phone had no token to begin with: the PC mints one for the cable, and
  /// storing it is what turns the connection into a pairing the user can
  /// see and revoke. A token session already had its token, and gets the
  /// same one back.
  String? get issuedToken => _issuedToken;

  String? _issuedToken;

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
    final generation = ++_connectionGeneration;
    _reconnectScheduledForGeneration = false;
    _initialOfferSent = false;
    _emit(PcConnectionPhase.connectingSignaling);
    final signaling = PcSignalingClient(candidate);
    _signaling = signaling;

    try {
      await signaling.connect();
    } catch (e) {
      if (generation != _connectionGeneration) return;
      _emit(PcConnectionPhase.error, message: 'Signaling connection failed: $e');
      _scheduleReconnect(generation);
      return;
    }

    _messagesSubscription = signaling.messages.listen(
      (message) => _handleMessage(message, generation),
      onDone: () => _handleSignalingDone(generation),
    );

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
      _issuedToken = ack.token;
    } catch (e) {
      if (generation != _connectionGeneration) return;
      _emit(PcConnectionPhase.error, message: 'Pairing handshake failed: $e');
      _scheduleReconnect(generation);
      return;
    }
    if (generation != _connectionGeneration) return;

    _emit(PcConnectionPhase.negotiating, pcId: ack.pcId, pcName: ack.pcName);

    final peerConnection = await createPeerConnection({'iceServers': <Map<String, dynamic>>[]});
    if (generation != _connectionGeneration) {
      // A newer attempt has already started while createPeerConnection was
      // in flight (e.g. this one's signaling/handshake was slow enough that
      // some other trigger already scheduled and started a replacement) —
      // don't let this one publish itself as the current connection.
      unawaited(peerConnection.close());
      return;
    }
    _peerConnection = peerConnection;

    peerConnection.onIceCandidate = (candidate) {
      if (generation != _connectionGeneration) return;
      if (candidate.candidate == null) return;
      signaling.send({
        'type': 'ice_candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
    peerConnection.onConnectionState = (state) => _handleConnectionState(state, generation, ack.pcId, ack.pcName);

    // HELP.md §8 "Leg A media track": attachExternalTrack's native addTrack()
    // (PublisherForegroundService.attachWebRtcLeg/attachWebRtcAudio, via the
    // third_party/flutter_webrtc patch) fires this once video/audio attach
    // mid-session. Without a handler here, that event was silently dropped —
    // no renegotiation offer was ever created or sent, so a paired PC could
    // never actually receive Leg A's tracks no matter how the phone-side
    // capture pipeline behaved. This reuses the exact same offer/send shape
    // as the initial connect below; unlike `_scheduleReconnect`, it never
    // touches signaling/hello — same already-authenticated WebSocket
    // session, no ICE restart, matching §8's "not a new connection" rule.
    peerConnection.onRenegotiationNeeded = () async {
      if (generation != _connectionGeneration) return;
      // Ignore anything fired before the initial offer below has actually
      // gone out (e.g. createDataChannel's own negotiation-needed flag) —
      // see _initialOfferSent's doc comment.
      if (!_initialOfferSent) return;
      final renegotiationOffer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(renegotiationOffer);
      signaling.send({'type': 'offer', 'sdp': renegotiationOffer.sdp});
    };

    _controlChannel = await peerConnection.createDataChannel('control', RTCDataChannelInit());
    if (generation != _connectionGeneration) return;

    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);
    if (generation != _connectionGeneration) return;
    signaling.send({'type': 'offer', 'sdp': offer.sdp});
    _initialOfferSent = true;

    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) => signaling.send({'type': 'ping'}));
  }

  void _handleMessage(Map<String, dynamic> message, int generation) {
    if (generation != _connectionGeneration) return;
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
        _scheduleReconnect(generation);
      case 'pong':
      case 'hello_ack':
        break;
    }
  }

  void _handleConnectionState(RTCPeerConnectionState state, int generation, String pcId, String pcName) {
    if (generation != _connectionGeneration) return;
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _reconnectAttempt = 0;
        _emit(PcConnectionPhase.connected, pcId: pcId, pcName: pcName);
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        if (!_closing) _scheduleReconnect(generation, pcId: pcId, pcName: pcName);
      default:
        break;
    }
  }

  void _handleSignalingDone(int generation) {
    if (generation != _connectionGeneration) return;
    if (!_closing) _scheduleReconnect(generation);
  }

  /// On WS drop or a failed peer connection, rebuilds a fresh
  /// `RTCPeerConnection` + offer rather than attempting an in-place ICE
  /// restart (deferred per PLAN.md — see HELP.md's reconnect section).
  /// Bounded backoff, then surfaces `disconnected` for a manual retry.
  ///
  /// [generation] must be the attempt that's actually failing — see
  /// `_connectionGeneration`'s doc comment for why a stale attempt's
  /// callback reaching here must be a no-op, and
  /// `_reconnectScheduledForGeneration`'s for why *two* live callbacks for
  /// the *same* still-current attempt must only schedule one retry between
  /// them.
  void _scheduleReconnect(int generation, {String? pcId, String? pcName}) {
    if (_closing) return;
    if (generation != _connectionGeneration) return;
    if (_reconnectScheduledForGeneration) return;
    _reconnectScheduledForGeneration = true;
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
