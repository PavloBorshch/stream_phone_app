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
import '../../features/capture/domain/broadcast_target.dart';
import '../../features/capture/domain/capture_mode.dart';
import '../../features/capture/presentation/broadcast_target_provider.dart';
import '../../features/destinations/presentation/destinations_provider.dart';
import '../../features/network_settings/domain/active_network.dart';
import '../../features/notifications/presentation/connection_alert_provider.dart';
import '../../features/network_settings/domain/network_settings.dart';
import '../../features/network_settings/presentation/network_settings_provider.dart';
import '../../features/pc_connection/data/pc_connection_platform.dart';
import '../../features/pc_connection/data/usb_bridge_discovery.dart';
import '../../features/pc_connection/presentation/usb_discovery_provider.dart';
import '../../features/pc_connection/presentation/usb_transport_preference.dart';
import '../../features/pc_connection/domain/discovered_pc.dart';
import '../../features/pc_connection/domain/paired_pc.dart';
import '../../features/pc_connection/presentation/paired_pcs_provider.dart';
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

/// Builds a [PcConnectionPlatform] for one connection attempt.
/// `PcConnectionPlatform` needs a per-call [PairingCandidate] (there's no
/// single long-lived instance the way `ScreencastPlatform`/`PublisherPlatform`
/// are), so the seam is a factory rather than a ready instance — overridden
/// in tests to exercise `connectToPc`'s success path (a connected PC, Leg A
/// attached) without a real WebRTC/native stack.
typedef PcConnectionPlatformFactory = PcConnectionPlatform Function(PairingCandidate candidate);

final pcConnectionPlatformFactoryProvider = Provider<PcConnectionPlatformFactory>((ref) {
  return PcConnectionPlatform.new;
});

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

    // Restores the user's broadcast-target choice from the previous session
    // (BroadcastTargetRepository) — everything else in `initial` starts
    // fresh on every launch, but this one is meant to survive a restart the
    // same way video/audio settings do.
    final broadcastTarget = ref.watch(broadcastTargetRepositoryProvider).read();
    return StreamSessionState.initial.copyWith(broadcastTarget: broadcastTarget);
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

  /// Broadcast-target selector action (capture screen, next to the mode
  /// toggle). Pure state switch plus persistence — mirrors [setMode] but
  /// also writes through `BroadcastTargetRepository` so the choice survives
  /// a restart. The capture screen disables the selector while a stream is
  /// live (see `BroadcastTargetSelector.enabled`), since the native
  /// publisher session is configured once at `start()` and has no path to
  /// retarget the PC/services split mid-stream.
  Future<void> setBroadcastTarget(BroadcastTarget target) async {
    if (target == state.broadcastTarget) return;
    state = state.copyWith(broadcastTarget: target);
    await ref.read(broadcastTargetRepositoryProvider).write(target);
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

    // The broadcast-target selection (capture screen, next to the mode
    // toggle) decides which of Leg A / Leg B this session asks for. Guard
    // the invalid combination up front with a message that says exactly
    // what to fix, rather than falling through to a generic "no usable
    // destination" once legs turn out empty.
    final target = state.broadcastTarget;
    final pcConnected = state.pcConnectionEvent.phase == PcConnectionPhase.connected;
    final pcPeerConnectionId = target.includesPc ? _pcConnection?.peerConnectionId : null;

    if (target.includesPc && (!pcConnected || pcPeerConnectionId == null)) {
      // "No PC is connected" is true but unhelpful on its own, and it was
      // actively misleading over USB: a user who has plugged the cable in
      // and can see the phone on the PC has every reason to think the PC
      // *is* connected. What is actually missing is one of several
      // different things, each needing a different action — so say which.
      state = state.copyWith(
        publisherEvent: PublisherEvent(
          status: PublisherStatus.error,
          message: await _noPcConnectedMessage(),
        ),
      );
      return;
    }
    // From here on, `target.includesPc` implies both a connected PC and a
    // resolved peer connection id — checked together above so a stale
    // `_pcConnection` (dropped between the phase check and this call, see
    // `PublishRequest.pcPeerConnectionId`'s doc comment) is reported as
    // clearly as an outright disconnect, rather than silently publishing
    // without Leg A.
    //
    // A PC reached over the USB tunnel takes the other route. Leg A's
    // WebRTC tracks cannot cross an `adb reverse` tunnel — it carries TCP
    // between two loopback addresses, and ICE has no candidate pair that
    // works across it — so attaching them would negotiate successfully,
    // send nothing, and leave the PC showing a phone tile that never gets a
    // frame. The cable's media rides an ordinary RTMP leg to the tunnelled
    // port instead, which is a single TCP connection and so exactly what
    // the tunnel does carry.
    final overUsb = _pcConnection?.connectedHost == '127.0.0.1';
    final includePcLeg = target.includesPc && !overUsb;

    final video = ref.read(videoSettingsProvider);
    final audio = ref.read(audioSettingsProvider);
    final repository = ref.read(destinationsRepositoryProvider);
    final enabledDestinations = repository.read().where((d) => d.enabled).toList();

    if (target.includesServices && enabledDestinations.isEmpty) {
      state = state.copyWith(
        publisherEvent: const PublisherEvent(
          status: PublisherStatus.error,
          message: 'No enabled destination — add one under Settings > '
              'Destinations & Accounts, or change what you\'re streaming to.',
        ),
      );
      return;
    }

    final legs = <PublishLeg>[];
    if (target.includesServices) {
      final missingKeys = <String>[];
      for (final destination in enabledDestinations) {
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

      if (legs.isEmpty) {
        // Every enabled destination's stream key was missing — fatal even
        // when the PC leg is also requested ("Both"): the user configured
        // services and expects them to work, so silently falling back to
        // PC-only would hide a real problem instead of surfacing it.
        state = state.copyWith(
          publisherEvent: PublisherEvent(
            status: PublisherStatus.error,
            message: 'No usable destination: the stream key for '
                '${missingKeys.join(', ')} is missing. Re-enter it under '
                'Settings > Destinations & Accounts.',
          ),
        );
        return;
      }
    }

    if (target.includesPc && overUsb) {
      // Published at the capture settings with no per-destination
      // overrides: this is not a destination the user configured, it is the
      // cable, and the PC compositor wants whatever the phone is capturing.
      legs.add(
        PublishLeg(
          destinationId: 'usb',
          displayName: 'PC (USB)',
          url: 'rtmp://127.0.0.1:${UsbBridgeDiscovery.mediaPort}/live',
          streamKey: 'phone',
          video: video,
        ),
      );
    }

    // `legs` is intentionally empty here exactly when `target ==
    // BroadcastTarget.toPc` over a *network* connection (services never
    // requested, media riding Leg A instead) — the native publisher
    // supports the PC leg as the only leg, so this is a normal request
    // handed to native, not an error condition caught here.

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
    _userDisconnectedPc = false;
    await _teardownPcConnection();

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

    final usbHost = await _usbHostFor(pc);
    final candidate = PairingCandidate(
      // The cable, when it is being used, is the *only* address dialled --
      // not merely the first.
      //
      // PcSignalingClient.connect races every host and keeps whichever
      // answers first, which is right for picking between a PC's Ethernet
      // and Wi-Fi addresses (they are equivalent) but wrong here: USB and
      // Wi-Fi are different transports with different media paths, and
      // racing them makes which one you get a coin flip. That is exactly
      // what happened -- a phone with a cable plugged in kept winning the
      // race over Wi-Fi and streaming WebRTC, while the USB source in the
      // compositor sat waiting for an RTMP publisher that was never coming.
      //
      // Falling back to the remembered network addresses when no cable is
      // in use, last working one first: the phone may be on a different
      // network than it paired on.
      hosts: usbHost != null ? [usbHost] : pc.knownHosts,
      port: pc.lastKnownPort,
      wsPath: pc.wsPath,
      authMethod: PairingAuthMethod.token,
      pcId: pc.pcId,
      token: token,
    );
    _attach(ref.read(pcConnectionPlatformFactoryProvider)(candidate));
    await _pcConnection!.connect();
  }

  /// Subscribes to a connection's events and installs the shared policy for
  /// them.
  void _attach(
    PcConnectionPlatform connection, {
    void Function(String token)? onPaired,
  }) {
    _pcConnection = connection;
    _pcConnectionSubscription = connection.events().listen((event) {
      state = state.copyWith(pcConnectionEvent: event);

      if (event.phase == PcConnectionPhase.connected) {
        final token = connection.issuedToken;
        if (token != null) onPaired?.call(token);
        return;
      }

      // `disconnected` is PcConnectionPlatform giving up after its own
      // bounded backoff. Its candidate's host list is fixed for its
      // lifetime, so a session pinned to the cable would keep retrying
      // loopback forever after the cable was pulled. Dropping the session
      // lets the next auto-connect tick re-decide the transport against
      // what is actually plugged in now.
      if (event.phase == PcConnectionPhase.disconnected &&
          identical(_pcConnection, connection)) {
        Future.microtask(() {
          if (identical(_pcConnection, connection)) _teardownPcConnection();
        });
      }
    });
  }

  /// Explains *why* no PC is connected, in terms of what the user can do
  /// about it right now.
  Future<String> _noPcConnectedMessage() async {
    final paired = ref.read(pairedPcRepositoryProvider).read();
    final overUsb = await ref.read(usbBridgeDiscoveryProvider).find();

    // A cable needs no pairing at all now, so a PC on the tunnel is always
    // "about to connect" rather than "needs setting up" -- the auto-connect
    // is already on its way.
    if (overUsb != null) {
      return 'Connecting to "${overUsb.pcName}" over USB - try again in a '
          'moment.';
    }

    return paired.isEmpty
        ? 'No PC is paired yet. Plug one in over USB, or pair it under '
              'Settings > PC Connection.'
        : 'No PC is connected. Connect to a paired PC under '
              'Settings > PC Connection, or change what you are streaming to.';
  }

  /// `127.0.0.1` when this PC should be reached over the USB cable right
  /// now, or null to use the network.
  ///
  /// Null whenever the user has turned [preferUsbTransportProvider] off, no
  /// tunnel is up, or the PC behind the tunnel is a different one. The
  /// tunnel's address is always loopback, which means nothing until adb has
  /// actually wired it to a PC, so it has to be probed rather than
  /// remembered.
  Future<String?> _usbHostFor(PairedPc pc) async {
    try {
      if (!ref.read(preferUsbTransportProvider)) return null;
      final found = await ref.read(usbBridgeDiscoveryProvider).find();
      if (found == null || found.pcId != pc.pcId) return null;
      return found.host;
    } catch (e) {
      // Never let USB discovery break a connect the network could handle.
      debugPrint('connectToPc: USB discovery failed: $e');
      return null;
    }
  }

  Future<void> disconnectFromPc() async {
    _userDisconnectedPc = true;
    await _teardownPcConnection();
  }

  Future<void> _teardownPcConnection() async {
    await _pcConnectionSubscription?.cancel();
    _pcConnectionSubscription = null;
    await _pcConnection?.dispose();
    _pcConnection = null;
    state = state.copyWith(pcConnectionEvent: PcConnectionEvent.idle);
  }

  /// Set by an explicit [disconnectFromPc]; cleared by an explicit
  /// [connectToPc]. Only the USB auto-connect consults it.
  bool _userDisconnectedPc = false;

  /// Connects to whatever PC is on the USB tunnel, if anything is.
  ///
  /// Driven by [usbAutoConnectProvider] from the app root rather than by a
  /// timer in here: this is app-level background behaviour, and owning a
  /// periodic timer inside a provider that every screen builds meant every
  /// widget test that pumped one could never settle.
  ///
  /// Without this, plugging the cable in did nothing on the phone: the PC
  /// would show the device and set up its tunnels, the phone would show
  /// nothing at all, and starting a stream failed with "No PC is
  /// connected" -- correctly, but for a reason the cable gave no hint of.
  /// The USB link is unambiguous in a way a network is not (there is
  /// exactly one machine on the other end of it, and the user just plugged
  /// it in), so connecting without being asked is the behaviour that
  /// matches what the cable already implies.
  ///
  /// Deliberately never *pairs*: it only connects to a PC that already has
  /// a stored token. Being reachable is not authorisation, and a cable
  /// silently granting a PC access to the camera would be a real hole --
  /// first-time pairing still goes through the QR/PIN handshake.
  Future<void> maybeAutoConnectOverUsb() async {
    if (_userDisconnectedPc) return;
    // A live session object means either a working connection or
    // PcConnectionPlatform's own backoff retrying one; both are better
    // than starting over from here.
    if (_pcConnection != null) return;

    try {
      if (!ref.read(preferUsbTransportProvider)) return;
      final found = await ref.read(usbBridgeDiscoveryProvider).find();
      if (found == null) return;

      // A PC already paired over the network keeps its stored token: that
      // identity is what the compositor's sources are keyed to, and
      // re-authenticating as a stranger over the cable would orphan them.
      for (final pc in ref.read(pairedPcRepositoryProvider).read()) {
        if (pc.pcId != found.pcId) continue;
        debugPrint('USB: auto-connecting to paired PC ${pc.displayName}');
        await connectToPc(pc);
        return;
      }

      debugPrint('USB: auto-connecting to unpaired PC ${found.pcName}');
      await connectOverUsb(found);
    } catch (e) {
      debugPrint('USB auto-connect check failed: $e');
    }
  }

  /// Connects to a PC over the USB cable with no pairing step at all.
  ///
  /// The cable is the credential. The PC accepts this only from a loopback
  /// peer — meaning a connection that arrived through its own `adb reverse`
  /// tunnel, which exists only because this phone's owner approved that
  /// PC's key in Android's "Allow USB debugging?" prompt. Anyone who can
  /// reach it therefore already holds adb access to this phone, which is
  /// strictly more than a camera feed. See [PairingAuthMethod.usb].
  ///
  /// The PC still answers with an ordinary pairing token, which is stored
  /// like any other, so the phone keeps a stable identity across reconnects
  /// and the PC shows up in the paired list where it can be revoked.
  /// Plugging in is a real pairing gesture — just not one that needs a PIN
  /// typed in.
  Future<void> connectOverUsb(DiscoveredPc pc) async {
    _userDisconnectedPc = false;
    await _teardownPcConnection();

    final candidate = PairingCandidate.overUsb(
      pcId: pc.pcId,
      port: pc.port,
      wsPath: pc.wsPath,
    );
    _attach(
      ref.read(pcConnectionPlatformFactoryProvider)(candidate),
      // The token the PC mints for this cable arrives with the successful
      // handshake; persisting it is what turns "connected right now" into a
      // pairing the user can see and revoke.
      onPaired: (token) => unawaited(
        ref
            .read(pairedPcsProvider.notifier)
            .addFromPairing(
              pcId: pc.pcId,
              displayName: pc.pcName,
              host: '127.0.0.1',
              port: pc.port,
              wsPath: pc.wsPath,
              token: token,
            ),
      ),
    );
    await _pcConnection!.connect();
  }
}

final streamSessionProvider = NotifierProvider<StreamSessionNotifier, StreamSessionState>(
  StreamSessionNotifier.new,
);
