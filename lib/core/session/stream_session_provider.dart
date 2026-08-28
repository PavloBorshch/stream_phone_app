import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/audio_settings/presentation/audio_settings_provider.dart';
import '../../features/battery_performance/data/battery_service.dart';
import '../../features/battery_performance/domain/battery_performance_settings.dart';
import '../../features/battery_performance/domain/device_health.dart';
import '../../features/battery_performance/domain/performance_guard_decision.dart';
import '../../features/battery_performance/presentation/battery_performance_provider.dart';
import '../../features/capture/domain/capture_mode.dart';
import '../../features/destinations/presentation/destinations_provider.dart';
import '../../features/network_settings/domain/active_network.dart';
import '../../features/notifications/presentation/connection_alert_provider.dart';
import '../../features/network_settings/domain/network_settings.dart';
import '../../features/network_settings/presentation/network_settings_provider.dart';
import '../../features/pc_connection/data/pc_connection_platform.dart';
import '../../features/pc_connection/domain/paired_pc.dart';
import '../../features/pc_connection/domain/pairing_session.dart';
import '../../features/pc_connection/domain/pc_connection_status.dart';
import '../../features/screencast/data/screencast_platform.dart';
import '../../features/screencast/domain/screencast_status.dart';
import '../../features/streaming_engine/domain/publish_request.dart';
import '../../features/streaming_engine/data/publisher_platform.dart';
import '../../features/streaming_engine/domain/publisher_event.dart';
import '../../features/streaming_engine/presentation/publisher_provider.dart';
import '../../features/video_settings/presentation/video_settings_provider.dart';
import '../persistence/secure_token_store_provider.dart';
import 'stream_session_state.dart';

final screencastPlatformProvider = Provider<ScreencastPlatform>((ref) => ScreencastPlatform());

class StreamSessionNotifier extends Notifier<StreamSessionState> {
  PcConnectionPlatform? _pcConnection;
  StreamSubscription<PcConnectionEvent>? _pcConnectionSubscription;

  @override
  StreamSessionState build() {
    final platform = ref.watch(screencastPlatformProvider);
    final publisher = ref.watch(publisherPlatformProvider);

    final subscription = platform.events().listen(_onScreencastEvent);
    final publisherSubscription = publisher.events().listen(
      (event) {
        state = state.copyWith(publisherEvent: event);
        _accountForBytes(event);
        // Reaches the user when the app isn't on screen, which is exactly the
        // case a foreground-service stream is designed for.
        unawaited(ref.read(connectionAlertServiceProvider).onStatusChanged(event));
      },
      // A build whose native publisher isn't present yet errors the stream
      // on first listen; that is "nothing is publishing", not a crash.
      onError: (Object error) => debugPrint('publisher event stream error: $error'),
    );
    ref.onDispose(() {
      subscription.cancel();
      publisherSubscription.cancel();
      _pcConnectionSubscription?.cancel();
      _pcConnection?.dispose();
    });

    // Picks up a screencast that's still running natively from before this
    // provider existed (e.g. the app was closed and reopened while
    // broadcasting) - the event stream alone would otherwise stay silent
    // until the native side next has something new to report.
    platform.getStatus().then((event) {
      state = state.copyWith(screencastEvent: event);
    });

    // Same race-cover for the publisher, which likewise outlives the Flutter
    // engine on Android (it runs in PublisherForegroundService): the app can
    // be reopened mid-stream and must show "live", not "idle".
    unawaited(_primePublisherStatus(publisher));

    // Wi-Fi-only is a policy that has to keep holding after the stream starts:
    // a phone walking out of Wi-Fi range would otherwise silently continue on
    // mobile data, which is the exact bill the setting exists to prevent.
    ref.listen<AsyncValue<ActiveNetwork>>(activeNetworkProvider, (previous, next) {
      final network = next.valueOrNull;
      if (network == null) return;
      _onNetworkChanged(network);
    });

    // Battery and thermal both feed one decision, so they share a listener
    // rather than racing to set conflicting ceilings.
    ref.listen<AsyncValue<BatteryStatus>>(batteryStatusProvider, (_, _) => _evaluateGuards());
    ref.listen<AsyncValue<ThermalStatus>>(thermalStatusProvider, (_, _) => _evaluateGuards());
    ref.listen<BatteryPerformanceSettings>(batteryPerformanceProvider, (_, _) => _evaluateGuards());

    return StreamSessionState.initial;
  }

  /// Bytes reported by the publisher are cumulative *within one session* and
  /// restart at zero for the next, so only forward deltas are counted — and
  /// only while the live link is metered.
  int _lastBytesSent = 0;

  void _accountForBytes(PublisherEvent event) {
    final total = event.bytesSent;
    if (total == null) return;
    final delta = total - _lastBytesSent;
    _lastBytesSent = total;
    if (delta <= 0) return;
    if (ref.read(activeNetworkProvider).valueOrNull?.isMetered != true) return;

    unawaited(ref.read(cellularUsageProvider.notifier).add(delta));
    _warnIfNearCap();
  }

  void _warnIfNearCap() {
    final settings = ref.read(networkSettingsProvider);
    final cap = settings.cellularDataCapMb;
    if (cap == null) return;
    final fraction = ref.read(cellularUsageProvider).fractionOfCap(cap);
    if (fraction == null) return;

    if (fraction >= 1) {
      _warn('Mobile data cap of $cap MB reached. Streaming is still running.');
    } else if (settings.warnBeforeCap && fraction >= NetworkSettings.warnThresholdFraction) {
      final percent = (fraction * 100).round();
      _warn('$percent% of the $cap MB mobile data cap used.');
    }
  }

  /// Warnings are latched rather than repeated: the stats tick fires every
  /// second, and re-raising the same message would bury the screen in
  /// snack bars.
  String? _lastWarning;

  void _warn(String message) {
    if (_lastWarning == message) return;
    _lastWarning = message;
    state = state.copyWith(networkWarning: message);
  }

  void clearNetworkWarning() {
    state = state.copyWith(clearNetworkWarning: true);
  }

  /// The ceiling currently pushed to the publisher, so an unchanged decision
  /// doesn't re-cross the channel every time the battery level ticks.
  PerformanceGuardDecision _lastDecision = PerformanceGuardDecision.unconstrained;

  void _evaluateGuards() {
    final decision = PerformanceGuardDecision.evaluate(
      settings: ref.read(batteryPerformanceProvider),
      battery: ref.read(batteryStatusProvider).valueOrNull ?? BatteryStatus.unknown,
      thermal: ref.read(thermalStatusProvider).valueOrNull ?? ThermalStatus.unknown,
    );
    if (decision == _lastDecision) return;
    _lastDecision = decision;

    if (decision.shouldStop) {
      // Only a running stream can be stopped; a guard tripping while idle
      // just means the user shouldn't be allowed to start, which
      // _startPublishing checks separately.
      if (state.isStreaming) {
        unawaited(stopStream());
        state = state.copyWith(
          publisherEvent: PublisherEvent(
            status: PublisherStatus.error,
            message: decision.reason,
          ),
        );
      }
      return;
    }

    unawaited(
      _applyQualityCeiling(decision.ceilingScale, decision.frameRateCap),
    );
    if (decision.reason != null && state.isStreaming) {
      _warn(decision.reason!);
    }
  }

  Future<void> _applyQualityCeiling(double scale, int frameRateCap) async {
    try {
      await ref
          .read(publisherPlatformProvider)
          .setQualityCeiling(scale: scale, frameRateCap: frameRateCap);
    } on MissingPluginException {
      // No native publisher in this build — nothing to cap.
    } on PlatformException catch (error) {
      debugPrint('setQualityCeiling failed: $error');
    }
  }

  void _onNetworkChanged(ActiveNetwork network) {
    if (!state.isStreaming) return;
    if (ref.read(networkSettingsProvider).preferredNetwork != PreferredNetwork.wifiOnly) return;
    if (!network.isMetered) return;

    unawaited(stopStream());
    state = state.copyWith(
      publisherEvent: const PublisherEvent(
        status: PublisherStatus.error,
        message: 'Stopped: the connection dropped to mobile data and '
            '"Wi-Fi only" is set under Settings > Network.',
      ),
    );
  }

  /// Whether policy allows a stream to start right now, as a message to show
  /// if it doesn't. Returns null when publishing is allowed.
  String? _networkPolicyBlocker() {
    final network = ref.read(activeNetworkProvider).valueOrNull;
    // An unknown network is not treated as a blocker: connectivity_plus can
    // report `other` for VPNs, and refusing to stream over one would be worse
    // than occasionally allowing a metered link through.
    if (network == null) return null;

    if (network == ActiveNetwork.none) {
      return 'No network connection.';
    }
    if (ref.read(networkSettingsProvider).preferredNetwork == PreferredNetwork.wifiOnly &&
        network.isMetered) {
      return 'On mobile data, but "Wi-Fi only" is set under Settings > Network.';
    }
    return null;
  }

  /// One-shot "what is the native publisher doing right now" query, kept
  /// separate from [build] so its failure modes are handled explicitly
  /// rather than through an async error nobody is listening for.
  Future<void> _primePublisherStatus(PublisherPlatform publisher) async {
    try {
      final event = await publisher.getStatus();
      // This answer describes the moment build() ran. The user can already
      // have tapped record (or hit the "nothing to publish to" error) while
      // the round trip was in flight, so it is only adopted if nothing has
      // moved the session on in the meantime — otherwise a stale "idle" would
      // overwrite live state.
      if (state.publisherEvent.status == PublisherStatus.idle) {
        state = state.copyWith(publisherEvent: event);
      }
    } on MissingPluginException {
      // Native publisher not present in this build — nothing is publishing.
    } on PlatformException catch (error) {
      debugPrint('publisher getStatus failed: $error');
    }
  }

  void _onScreencastEvent(ScreencastEvent event) {
    state = state.copyWith(screencastEvent: event);

    // A screencast started via the record button only reaches the point where
    // it can be published once native capture is actually running, so the
    // publish step is deferred to here rather than run alongside
    // requestCapture(). pendingScreencastPublish keeps this from firing for a
    // screencast that was already in progress when the app reopened.
    if (state.pendingScreencastPublish && event.status == ScreencastStatus.capturing) {
      state = state.copyWith(pendingScreencastPublish: false);
      unawaited(_startPublishing(CaptureMode.screencast));
    } else if (state.pendingScreencastPublish &&
        (event.status == ScreencastStatus.denied ||
            event.status == ScreencastStatus.stopped ||
            event.status == ScreencastStatus.error)) {
      state = state.copyWith(pendingScreencastPublish: false);
    }
  }

  /// Pure state switch — no native calls. `CaptureScreen._onModeChanged`
  /// stops any active screencast capture/stream *before* calling this (the
  /// same "sequence native calls at the widget layer" split
  /// `_onRecordButtonTap` uses), so by the time this runs there is nothing
  /// left running to reconcile. Deliberately leaves screencastEvent
  /// untouched regardless — if a caller ever does invoke this while a
  /// screencast is still active, the real status will arrive shortly via
  /// the native event stream anyway, and resetting it here would just be a
  /// stale guess in between.
  void setMode(CaptureMode mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode);
  }

  /// Record-button action. In camera mode this starts publishing straight
  /// away; in screencast mode the system consent dialog has to be cleared
  /// first, so it only records the intent and requests capture — see
  /// [_onScreencastEvent].
  Future<void> startStream() async {
    if (state.isStreaming) return;

    if (state.mode == CaptureMode.screencast) {
      if (state.screencastEvent.status == ScreencastStatus.capturing) {
        await _startPublishing(CaptureMode.screencast);
        return;
      }
      state = state.copyWith(pendingScreencastPublish: true);
      await ref.read(screencastPlatformProvider).requestCapture();
      return;
    }

    await _startPublishing(CaptureMode.camera);
  }

  Future<void> _startPublishing(CaptureMode source) async {
    final blocker = _networkPolicyBlocker();
    if (blocker != null) {
      state = state.copyWith(
        publisherEvent: PublisherEvent(status: PublisherStatus.error, message: blocker),
      );
      return;
    }

    final video = ref.read(videoSettingsProvider);
    final audio = ref.read(audioSettingsProvider);
    final repository = ref.read(destinationsRepositoryProvider);
    final destinations = repository.read().where((d) => d.enabled).toList();

    final legs = <PublishLeg>[];
    final missingKeys = <String>[];
    for (final destination in destinations) {
      final streamKey = await repository.readStreamKey(destination.secureKeyId);
      if (streamKey == null || streamKey.isEmpty) {
        // The destination survives in the list but its key is gone from
        // secure storage (a restore onto a new device does exactly this) —
        // publish the rest rather than failing the whole session.
        missingKeys.add(destination.displayName);
        continue;
      }
      legs.add(
        PublishLeg(
          destinationId: destination.id,
          displayName: destination.displayName,
          url: destination.rtmpUrl,
          streamKey: streamKey,
          video: destination.overrides.applyTo(video),
        ),
      );
    }

    // PLAN.md §1.5's "Leg A", video-only (see HELP.md §8's "Leg A media
    // track" section for the protocol and PLAN.md Phase 5's "Outstanding"
    // note for what's still missing — no audio yet, and nothing on the PC
    // side can receive this until that repo's own work lands). Riding along
    // with at least one Leg B destination rather than standing alone: the
    // native publisher session (camera/mic + mixer) only exists while a
    // Leg B stream is running, so a PC-only stream with zero RTMP
    // destinations still isn't possible — see the `legs.isEmpty` branch
    // below.
    final includePcLeg = state.pcConnectionEvent.phase == PcConnectionPhase.connected;
    final pcPeerConnectionId = includePcLeg ? _pcConnection?.peerConnectionId : null;

    if (legs.isEmpty) {
      state = state.copyWith(
        publisherEvent: PublisherEvent(
          status: PublisherStatus.error,
          message: switch ((missingKeys.isNotEmpty, includePcLeg)) {
            (true, _) => 'No usable destination: the stream key for '
                '${missingKeys.join(', ')} is missing. Re-enter it under '
                'Settings > Destinations & Accounts.',
            (false, true) => 'Streaming to a paired PC on its own (with no '
                'RTMP destination) isn\'t supported yet. Add an RTMP '
                'destination under Settings > Destinations & Accounts to '
                'stream — the paired PC will also receive the video.',
            (false, false) => 'No enabled destination — add one under '
                'Settings > Destinations & Accounts.',
          },
        ),
      );
      return;
    }

    _lastBytesSent = 0;
    _lastWarning = null;
    ref.read(connectionAlertServiceProvider).reset();
    // Re-assert whatever the guards currently want: the native session is
    // brand new and starts with no ceiling of its own.
    unawaited(_applyQualityCeiling(_lastDecision.ceilingScale, _lastDecision.frameRateCap));
    state = state.copyWith(
      publisherEvent: const PublisherEvent(status: PublisherStatus.connecting),
      clearNetworkWarning: true,
    );

    try {
      await ref
          .read(publisherPlatformProvider)
          .start(
            PublishRequest(
              source: source,
              video: video,
              audio: audio,
              legs: legs,
              includePcLeg: includePcLeg,
              pcPeerConnectionId: pcPeerConnectionId,
            ),
          );
    } on PlatformException catch (error) {
      state = state.copyWith(
        publisherEvent: PublisherEvent(
          status: PublisherStatus.error,
          message: error.message ?? 'Could not start publishing.',
        ),
      );
    } on MissingPluginException {
      state = state.copyWith(
        publisherEvent: const PublisherEvent(
          status: PublisherStatus.error,
          message: 'Publishing is not available on this build yet.',
        ),
      );
    }
  }

  Future<void> stopStream() async {
    state = state.copyWith(pendingScreencastPublish: false);
    try {
      await ref.read(publisherPlatformProvider).stop();
    } on MissingPluginException {
      // Nothing was publishing; fall through to the local reset below.
    }
    state = state.copyWith(publisherEvent: const PublisherEvent(status: PublisherStatus.stopped));
  }

  /// Mutes/unmutes the mic mid-stream without interrupting the session.
  Future<void> setMuted(bool muted) async {
    if (muted == state.isMuted) return;
    state = state.copyWith(isMuted: muted);
    try {
      await ref.read(publisherPlatformProvider).setMuted(muted);
    } on MissingPluginException {
      // No live publisher to mute — the flag still holds for the next start.
    }
  }

  /// Opens a WebRTC connection to an already-paired PC (see
  /// `PcConnectionPlatform`'s doc comment) — reads its stored token, then
  /// tracks the connection's live status in [StreamSessionState
  /// .pcConnectionEvent], same role the screencast subscription above plays
  /// for [StreamSessionState.screencastEvent].
  Future<void> connectToPc(PairedPc pc) async {
    await disconnectFromPc();

    final token = await ref.read(secureTokenStoreProvider).read(pc.secureTokenId);
    if (token == null) {
      state = state.copyWith(
        pcConnectionEvent: PcConnectionEvent(
          phase: PcConnectionPhase.error,
          pcId: pc.pcId,
          pcName: pc.displayName,
          message: 'No stored pairing token for this PC — re-pair it.',
        ),
      );
      return;
    }

    final candidate = PairingCandidate(
      // Every address this PC advertised when it was paired, last working
      // one first — the phone may now be on a different network than it
      // paired on, so the previously-working address isn't guaranteed.
      hosts: pc.knownHosts,
      port: pc.lastKnownPort,
      wsPath: pc.wsPath,
      authMethod: PairingAuthMethod.token,
      pcId: pc.pcId,
      token: token,
    );
    final connection = PcConnectionPlatform(candidate);
    _pcConnection = connection;
    _pcConnectionSubscription = connection.events().listen((event) {
      state = state.copyWith(pcConnectionEvent: event);
    });
    await connection.connect();
  }

  Future<void> disconnectFromPc() async {
    await _pcConnectionSubscription?.cancel();
    _pcConnectionSubscription = null;
    await _pcConnection?.dispose();
    _pcConnection = null;
    state = state.copyWith(pcConnectionEvent: PcConnectionEvent.idle);
  }
}

final streamSessionProvider = NotifierProvider<StreamSessionNotifier, StreamSessionState>(
  StreamSessionNotifier.new,
);
