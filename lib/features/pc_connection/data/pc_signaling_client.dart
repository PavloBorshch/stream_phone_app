import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/pairing_session.dart';

/// Thrown when the PC's `hello_ack` reports `ok: false` — see HELP.md's
/// "WebSocket signaling protocol" section for the `error` codes
/// (`invalid_token`, `invalid_pin`, `expired`, `rate_limited`).
class PairingRejectedException implements Exception {
  const PairingRejectedException(this.errorCode);

  final String errorCode;

  @override
  String toString() => 'PC rejected pairing: $errorCode';
}

/// Thrown when none of a [PairingCandidate]'s addresses could be reached.
/// Carries the per-address failure so the message can distinguish "wrong
/// network" (timeouts everywhere) from "PC not listening" (refused).
class PcUnreachableException implements Exception {
  const PcUnreachableException(this.failures);

  /// Host → the error that address failed with, in dial order.
  final Map<String, Object> failures;

  @override
  String toString() {
    final detail = failures.entries.map((e) => '${e.key} (${e.value})').join(', ');
    return 'Could not reach the PC at any of its addresses: $detail';
  }
}

/// Result of a successful `hello`/`hello_ack` exchange — enough to persist
/// via [PairedPcRepository.addFromPairing].
class PairingResult {
  const PairingResult({
    required this.pcId,
    required this.pcName,
    required this.token,
    required this.host,
  });

  final String pcId;
  final String pcName;
  final String token;

  /// The address that actually answered — persisted as the PC's
  /// `lastKnownHost` so the next reconnect tries the working one first.
  final String host;
}

/// Speaks the WebSocket signaling protocol documented in HELP.md: connects
/// to the PC's local `ws://<host>:<port><wsPath>` server, sends `hello`,
/// and exposes the decoded JSON message stream for whatever comes after
/// (the WebRTC SDP/ICE exchange, driven by `PcConnectionPlatform`).
///
/// This class only owns the socket and JSON framing — it doesn't know
/// anything about WebRTC. That keeps the initial credential-validating
/// handshake ([pairOnce]) usable on its own from the pairing screens,
/// without pulling in `flutter_webrtc`.
class PcSignalingClient {
  PcSignalingClient(this._candidate);

  final PairingCandidate _candidate;
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _messagesController;
  StreamSubscription<dynamic>? _rawSubscription;
  String? _connectedHost;

  /// Which of the candidate's [PairingCandidate.hosts] answered. Null until
  /// [connect] succeeds.
  String? get connectedHost => _connectedHost;

  /// Dials every address in [PairingCandidate.hosts] **concurrently** and
  /// keeps the first WebSocket that completes its handshake, closing the
  /// rest.
  ///
  /// Racing rather than trying addresses in sequence matters because an
  /// unreachable address fails by *timing out* (the phone has no route, so
  /// nothing is ever transmitted and no RST comes back), not by failing
  /// fast — dialing serially would cost `connectTimeout` per dead address
  /// before reaching a live one. Racing keeps the worst case at one
  /// timeout regardless of how many interfaces the PC advertised.
  ///
  /// The race deliberately covers only the transport handshake, not
  /// `hello` — [sendHello] runs on the single winning socket, so a
  /// one-shot QR token is never spent more than once.
  Future<void> connect({Duration connectTimeout = const Duration(seconds: 8)}) async {
    final (host, channel) = await _raceConnect(connectTimeout);
    _connectedHost = host;
    _channel = channel;

    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _messagesController = controller;
    _rawSubscription = channel.stream.listen(
      (raw) => controller.add(jsonDecode(raw as String) as Map<String, dynamic>),
      onError: controller.addError,
      onDone: controller.close,
    );
  }

  Future<(String, WebSocketChannel)> _raceConnect(Duration connectTimeout) async {
    final winner = Completer<(String, WebSocketChannel)>();
    final failures = <String, Object>{};
    final dialled = <String, WebSocketChannel>{};

    for (final host in _candidate.hosts) {
      final uri = Uri(scheme: 'ws', host: host, port: _candidate.port, path: _candidate.wsPath);
      final WebSocketChannel channel;
      try {
        // Synchronous — `connect` returns immediately and the handshake
        // runs behind `ready`, so every address is in flight at once.
        channel = WebSocketChannel.connect(uri);
      } catch (e) {
        _recordFailure(host, e, failures, winner);
        continue;
      }
      dialled[host] = channel;

      unawaited(
        channel.ready
            .timeout(connectTimeout)
            .then(
              (_) {
                if (!winner.isCompleted) winner.complete((host, channel));
              },
              onError: (Object e) => _recordFailure(host, e, failures, winner),
            ),
      );
    }

    if (dialled.isEmpty && !winner.isCompleted) {
      throw PcUnreachableException(failures);
    }

    try {
      final result = await winner.future;
      for (final entry in dialled.entries) {
        if (!identical(entry.value, result.$2)) unawaited(entry.value.sink.close());
      }
      return result;
    } catch (_) {
      for (final channel in dialled.values) {
        unawaited(channel.sink.close());
      }
      rethrow;
    }
  }

  void _recordFailure(
    String host,
    Object error,
    Map<String, Object> failures,
    Completer<(String, WebSocketChannel)> winner,
  ) {
    failures[host] = error;
    // Only the last address still in flight reports the overall failure —
    // one dead interface must not sink a race another address can still win.
    if (failures.length == _candidate.hosts.length && !winner.isCompleted) {
      winner.completeError(PcUnreachableException(failures));
    }
  }

  Stream<Map<String, dynamic>> get messages {
    final controller = _messagesController;
    if (controller == null) {
      throw StateError('PcSignalingClient.connect() must complete before reading messages');
    }
    return controller.stream;
  }

  void send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) throw StateError('PcSignalingClient.connect() must complete before send()');
    channel.sink.add(jsonEncode(message));
  }

  void sendHello() {
    send({
      'type': 'hello',
      'role': 'phone',
      'protocolVersion': 1,
      'auth': switch (_candidate.authMethod) {
        PairingAuthMethod.token => {'method': 'token', 'pcId': _candidate.pcId, 'token': _candidate.token},
        PairingAuthMethod.pin => {'method': 'pin', 'pin': _candidate.pin},
      },
    });
  }

  Future<void> close() async {
    await _rawSubscription?.cancel();
    await _messagesController?.close();
    await _channel?.sink.close();
    _channel = null;
    _messagesController = null;
    _rawSubscription = null;
  }

  /// Connects, sends `hello`, waits for `hello_ack`, then closes — used by
  /// the pairing screens (QR scan / PIN entry) to validate credentials and
  /// obtain the token to persist, without keeping a connection open. The
  /// real WebRTC session (`PcConnectionPlatform`) opens its own connection
  /// later and re-runs this same handshake.
  static Future<PairingResult> pairOnce(
    PairingCandidate candidate, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final client = PcSignalingClient(candidate);
    try {
      await client.connect();
      final ackFuture = client.messages.firstWhere((m) => m['type'] == 'hello_ack');
      client.sendHello();
      final ack = await ackFuture.timeout(timeout);

      if (ack['ok'] != true) {
        throw PairingRejectedException(ack['error'] as String? ?? 'unknown');
      }
      return PairingResult(
        pcId: ack['pcId'] as String,
        pcName: ack['pcName'] as String,
        token: ack['token'] as String,
        host: client.connectedHost!,
      );
    } finally {
      await client.close();
    }
  }
}
