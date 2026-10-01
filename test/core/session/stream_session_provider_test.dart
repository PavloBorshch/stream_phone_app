import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/secure_token_store.dart';
import 'package:stream_phone_cam/core/persistence/secure_token_store_provider.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository_provider.dart';
import 'package:stream_phone_cam/core/session/stream_session_provider.dart';
import 'package:stream_phone_cam/features/battery_performance/data/battery_service.dart';
import 'package:stream_phone_cam/features/battery_performance/domain/device_health.dart';
import 'package:stream_phone_cam/features/battery_performance/presentation/battery_performance_provider.dart';
import 'package:stream_phone_cam/features/capture/data/broadcast_target_repository.dart';
import 'package:stream_phone_cam/features/capture/domain/broadcast_target.dart';
import 'package:stream_phone_cam/features/capture/domain/capture_mode.dart';
import 'package:stream_phone_cam/features/destinations/data/destinations_repository.dart';
import 'package:stream_phone_cam/features/destinations/domain/stream_destination.dart';
import 'package:stream_phone_cam/features/network_settings/domain/active_network.dart';
import 'package:stream_phone_cam/features/network_settings/domain/network_settings.dart';
import 'package:stream_phone_cam/features/network_settings/presentation/network_settings_provider.dart';
import 'package:stream_phone_cam/features/pc_connection/data/pc_connection_platform.dart';
import 'package:stream_phone_cam/features/pc_connection/data/usb_bridge_discovery.dart';
import 'package:stream_phone_cam/features/pc_connection/domain/discovered_pc.dart';
import 'package:stream_phone_cam/features/pc_connection/domain/paired_pc.dart';
import 'package:stream_phone_cam/features/pc_connection/domain/pairing_session.dart';
import 'package:stream_phone_cam/features/pc_connection/presentation/paired_pcs_provider.dart';
import 'package:stream_phone_cam/features/pc_connection/presentation/usb_auto_connect.dart';
import 'package:stream_phone_cam/features/pc_connection/presentation/usb_discovery_provider.dart';
import 'package:stream_phone_cam/features/pc_connection/presentation/usb_transport_preference.dart';
import 'package:stream_phone_cam/features/pc_connection/domain/pc_connection_status.dart';
import 'package:stream_phone_cam/features/screencast/data/screencast_platform.dart';
import 'package:stream_phone_cam/features/screencast/domain/screencast_status.dart';
import 'package:stream_phone_cam/features/streaming_engine/data/publisher_platform.dart';
import 'package:stream_phone_cam/features/streaming_engine/domain/publish_request.dart';
import 'package:stream_phone_cam/features/streaming_engine/domain/publisher_event.dart';
import 'package:stream_phone_cam/features/streaming_engine/presentation/publisher_provider.dart';
import 'package:stream_phone_cam/features/video_settings/domain/video_overrides.dart';
import 'package:stream_phone_cam/features/video_settings/domain/video_settings.dart';

class MockScreencastPlatform extends Mock implements ScreencastPlatform {}

class MockPublisherPlatform extends Mock implements PublisherPlatform {}

class MockSecureTokenStore extends Mock implements SecureTokenStore {}

class MockPcConnectionPlatform extends Mock implements PcConnectionPlatform {}

class _FakePublishRequest extends Fake implements PublishRequest {}

/// Returns whatever a test sets, so the USB auto-connect can be exercised
/// without a cable -- and so every *other* test in this file stops making a
/// real loopback request on every provider build.
class _FakeUsbBridgeDiscovery implements UsbBridgeDiscovery {
  DiscoveredPc? pc;

  @override
  Future<DiscoveredPc?> find({Duration timeout = const Duration(seconds: 1)}) async => pc;
}

void main() {
  late MockScreencastPlatform platform;
  late MockPublisherPlatform publisher;
  late MockSecureTokenStore secureStore;
  late MockPcConnectionPlatform pcConnection;
  late SettingsRepository settings;
  late ProviderContainer container;
  late StreamController<PublisherEvent> publisherEvents;
  late StreamController<PcConnectionEvent> pcConnectionEvents;

  setUpAll(() {
    registerFallbackValue(_FakePublishRequest());
  });

  /// The network the fake connectivity layer reports. Defaults to Wi-Fi so
  /// policy never blocks the tests that aren't about policy.
  late _FakeUsbBridgeDiscovery usbDiscovery;
  late List<PairingCandidate> capturedCandidates;
  late ActiveNetwork activeNetwork;
  late BatteryStatus batteryStatus;
  late ThermalStatus thermalStatus;

  ProviderContainer buildContainer() {
    final c = ProviderContainer(
      overrides: [
        screencastPlatformProvider.overrideWithValue(platform),
        publisherPlatformProvider.overrideWithValue(publisher),
        settingsRepositoryProvider.overrideWithValue(settings),
        secureTokenStoreProvider.overrideWithValue(secureStore),
        activeNetworkProvider.overrideWith((ref) => Stream.value(activeNetwork)),
        // Battery and thermal reach for platform channels the moment they are
        // watched, so they are faked here; the defaults are "plugged in and
        // cool", i.e. no guard should ever trip unless a test asks for it.
        batteryStatusProvider.overrideWith((ref) => Stream.value(batteryStatus)),
        thermalStatusProvider.overrideWith((ref) => Stream.value(thermalStatus)),
        // Swaps out the real WebRTC/native `PcConnectionPlatform` for a mock
        // so `connectToPc`'s success path (PC connects, `peerConnectionId`
        // resolves) can be exercised without a real signaling/WebRTC stack.
        pcConnectionPlatformFactoryProvider.overrideWithValue((candidate) {
          capturedCandidates.add(candidate);
          return pcConnection;
        }),
        usbBridgeDiscoveryProvider.overrideWithValue(usbDiscovery),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    usbDiscovery = _FakeUsbBridgeDiscovery();
    capturedCandidates = [];
    settings = await SettingsRepository.create();
    activeNetwork = ActiveNetwork.wifi;
    batteryStatus = BatteryStatus.unknown;
    thermalStatus = ThermalStatus.none;

    platform = MockScreencastPlatform();
    when(() => platform.events()).thenAnswer((_) => const Stream.empty());
    when(() => platform.getStatus()).thenAnswer((_) async => ScreencastEvent.idle);
    when(() => platform.requestCapture()).thenAnswer((_) async {});

    publisher = MockPublisherPlatform();
    publisherEvents = StreamController<PublisherEvent>.broadcast();
    addTearDown(publisherEvents.close);
    when(() => publisher.events()).thenAnswer((_) => publisherEvents.stream);
    when(() => publisher.getStatus()).thenAnswer((_) async => PublisherEvent.idle);
    when(() => publisher.start(any())).thenAnswer((_) async {});
    when(() => publisher.stop()).thenAnswer((_) async {});
    when(
      () => publisher.setQualityCeiling(
        scale: any(named: 'scale'),
        frameRateCap: any(named: 'frameRateCap'),
      ),
    ).thenAnswer((_) async {});
    when(() => publisher.setMuted(any())).thenAnswer((_) async {});

    secureStore = MockSecureTokenStore();
    when(() => secureStore.write(any(), any())).thenAnswer((_) async {});
    when(() => secureStore.delete(any())).thenAnswer((_) async {});
    when(() => secureStore.read(any())).thenAnswer((_) async => 'stream-key');

    pcConnection = MockPcConnectionPlatform();
    pcConnectionEvents = StreamController<PcConnectionEvent>.broadcast();
    addTearDown(pcConnectionEvents.close);
    when(() => pcConnection.events()).thenAnswer((_) => pcConnectionEvents.stream);
    when(() => pcConnection.connect()).thenAnswer((_) async {});
    when(() => pcConnection.dispose()).thenAnswer((_) async {});
    when(() => pcConnection.peerConnectionId).thenReturn('peer-1');
    when(() => pcConnection.issuedToken).thenReturn(null);
  });

  final testPairedPc = PairedPc(
    pcId: 'pc-1',
    displayName: "Alex's PC",
    lastKnownHost: '192.168.1.42',
    otherKnownHosts: const [],
    lastKnownPort: 58712,
    wsPath: '/pair',
    secureTokenId: 'pc-1-token',
    pairedAt: DateTime(2026, 8, 28),
  );

  /// Connects to [testPairedPc] via the mocked [pcConnection] and pushes a
  /// `connected` event, mirroring what a real successful handshake would
  /// report — the seam this test file exists to exercise.
  Future<void> connectMockPc(ProviderContainer container) async {
    await container.read(streamSessionProvider.notifier).connectToPc(testPairedPc);
    pcConnectionEvents.add(
      const PcConnectionEvent(phase: PcConnectionPhase.connected, pcId: 'pc-1', pcName: "Alex's PC"),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<StreamDestination> addDestination({VideoOverrides? overrides}) async {
    final repository = DestinationsRepository(settings, secureStore);
    final destination = await repository.add(
      platform: StreamPlatform.custom,
      displayName: 'My RTMP',
      rtmpUrl: 'rtmp://example.com/live',
      streamKey: 'stream-key',
    );
    if (overrides != null) {
      await repository.setOverrides(destination.id, overrides);
    }
    return destination;
  }

  test('starts in camera mode with an idle screencast event', () {
    container = buildContainer();
    final state = container.read(streamSessionProvider);
    expect(state.mode, CaptureMode.camera);
    expect(state.screencastEvent.status, ScreencastStatus.idle);
    expect(state.publisherEvent.status, PublisherStatus.idle);
  });

  test('getStatus() result on startup is picked up (covers native/Dart attach race)', () async {
    when(() => platform.getStatus()).thenAnswer(
      (_) async => const ScreencastEvent(status: ScreencastStatus.capturing),
    );
    container = buildContainer();

    container.read(streamSessionProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(streamSessionProvider).screencastEvent.status, ScreencastStatus.capturing);
  });

  test('publisher getStatus() on startup is picked up (app reopened mid-stream)', () async {
    when(() => publisher.getStatus()).thenAnswer(
      (_) async => const PublisherEvent(status: PublisherStatus.live, bitrateKbps: 4200),
    );
    container = buildContainer();

    container.read(streamSessionProvider);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(streamSessionProvider);
    expect(state.publisherEvent.status, PublisherStatus.live);
    expect(state.isStreaming, isTrue);
  });

  test('setMode switches mode without resetting an in-progress screencast event', () async {
    when(() => platform.getStatus()).thenAnswer(
      (_) async => const ScreencastEvent(status: ScreencastStatus.capturing),
    );
    container = buildContainer();
    container.read(streamSessionProvider);
    await Future<void>.delayed(Duration.zero);

    container.read(streamSessionProvider.notifier).setMode(CaptureMode.screencast);

    final state = container.read(streamSessionProvider);
    expect(state.mode, CaptureMode.screencast);
    expect(state.screencastEvent.status, ScreencastStatus.capturing);
  });

  test('events stream updates screencastEvent', () async {
    final controller = StreamController<ScreencastEvent>();
    addTearDown(controller.close);
    when(() => platform.events()).thenAnswer((_) => controller.stream);
    container = buildContainer();
    container.read(streamSessionProvider);

    controller.add(const ScreencastEvent(status: ScreencastStatus.paused));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(streamSessionProvider).screencastEvent.status, ScreencastStatus.paused);
  });

  test('publisher events stream updates publisherEvent', () async {
    final controller = StreamController<PublisherEvent>();
    addTearDown(controller.close);
    when(() => publisher.events()).thenAnswer((_) => controller.stream);
    container = buildContainer();
    container.read(streamSessionProvider);

    controller.add(const PublisherEvent(status: PublisherStatus.live, fps: 30));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(streamSessionProvider).publisherEvent.fps, 30);
  });

  test('startStream in camera mode publishes every enabled destination', () async {
    await addDestination();
    container = buildContainer();
    container.read(streamSessionProvider);

    await container.read(streamSessionProvider.notifier).startStream();

    final request = verify(() => publisher.start(captureAny())).captured.single as PublishRequest;
    expect(request.source, CaptureMode.camera);
    expect(request.legs, hasLength(1));
    expect(request.legs.single.url, 'rtmp://example.com/live');
    expect(request.legs.single.streamKey, 'stream-key');
    expect(request.includePcLeg, isFalse);
  });

  test('per-destination overrides win over the global video settings', () async {
    await addDestination(
      overrides: const VideoOverrides(resolution: VideoResolution.p720, bitrateKbps: 2500),
    );
    container = buildContainer();
    container.read(streamSessionProvider);

    await container.read(streamSessionProvider.notifier).startStream();

    final request = verify(() => publisher.start(captureAny())).captured.single as PublishRequest;
    final leg = request.legs.single;
    // Overridden fields take the destination's value...
    expect(leg.video.resolution, VideoResolution.p720);
    expect(leg.video.bitrateKbps, 2500);
    // ...while unset ones still follow the global settings.
    expect(leg.video.frameRate, request.video.frameRate);
    // The capture/encode config itself is unaffected by a per-leg override.
    expect(request.video.resolution, VideoSettings.defaults.resolution);
  });

  test('a destination whose stream key is gone is skipped, not fatal', () async {
    await addDestination();
    await addDestination();
    var call = 0;
    when(() => secureStore.read(any())).thenAnswer((_) async => call++ == 0 ? null : 'stream-key');
    container = buildContainer();
    container.read(streamSessionProvider);

    await container.read(streamSessionProvider.notifier).startStream();

    final request = verify(() => publisher.start(captureAny())).captured.single as PublishRequest;
    expect(request.legs, hasLength(1));
  });

  test('startStream with nothing to publish to reports an error instead of calling native',
      () async {
    container = buildContainer();
    container.read(streamSessionProvider);

    await container.read(streamSessionProvider.notifier).startStream();

    verifyNever(() => publisher.start(any()));
    final state = container.read(streamSessionProvider);
    expect(state.publisherEvent.status, PublisherStatus.error);
    expect(state.publisherEvent.message, contains('No enabled destination'));
  });

  test('startStream in screencast mode requests capture first and publishes once capturing',
      () async {
    final controller = StreamController<ScreencastEvent>();
    addTearDown(controller.close);
    when(() => platform.events()).thenAnswer((_) => controller.stream);
    await addDestination();
    container = buildContainer();
    container.read(streamSessionProvider);
    container.read(streamSessionProvider.notifier).setMode(CaptureMode.screencast);

    await container.read(streamSessionProvider.notifier).startStream();

    verify(() => platform.requestCapture()).called(1);
    verifyNever(() => publisher.start(any()));
    expect(container.read(streamSessionProvider).pendingScreencastPublish, isTrue);

    controller.add(const ScreencastEvent(status: ScreencastStatus.capturing, textureId: 7));
    await Future<void>.delayed(Duration.zero);

    final request = verify(() => publisher.start(captureAny())).captured.single as PublishRequest;
    expect(request.source, CaptureMode.screencast);
    expect(container.read(streamSessionProvider).pendingScreencastPublish, isFalse);
  });

  test('a screencast already running at startup does not start publishing on its own', () async {
    final controller = StreamController<ScreencastEvent>();
    addTearDown(controller.close);
    when(() => platform.events()).thenAnswer((_) => controller.stream);
    await addDestination();
    container = buildContainer();
    container.read(streamSessionProvider);

    controller.add(const ScreencastEvent(status: ScreencastStatus.capturing, textureId: 7));
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => publisher.start(any()));
  });

  test('a denied capture consent clears the pending publish intent', () async {
    final controller = StreamController<ScreencastEvent>();
    addTearDown(controller.close);
    when(() => platform.events()).thenAnswer((_) => controller.stream);
    await addDestination();
    container = buildContainer();
    container.read(streamSessionProvider);
    container.read(streamSessionProvider.notifier).setMode(CaptureMode.screencast);
    await container.read(streamSessionProvider.notifier).startStream();

    controller.add(const ScreencastEvent(status: ScreencastStatus.denied));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(streamSessionProvider).pendingScreencastPublish, isFalse);
    verifyNever(() => publisher.start(any()));
  });

  test('stopStream stops the native publisher and clears the session', () async {
    await addDestination();
    container = buildContainer();
    container.read(streamSessionProvider);
    await container.read(streamSessionProvider.notifier).startStream();

    await container.read(streamSessionProvider.notifier).stopStream();

    verify(() => publisher.stop()).called(1);
    expect(container.read(streamSessionProvider).publisherEvent.status, PublisherStatus.stopped);
    expect(container.read(streamSessionProvider).isStreaming, isFalse);
  });

  test('setMuted forwards to the publisher and is idempotent', () async {
    container = buildContainer();
    container.read(streamSessionProvider);

    await container.read(streamSessionProvider.notifier).setMuted(true);
    await container.read(streamSessionProvider.notifier).setMuted(true);

    verify(() => publisher.setMuted(true)).called(1);
    expect(container.read(streamSessionProvider).isMuted, isTrue);
  });

  group('network policy', () {
    Future<ProviderContainer> startedContainer() async {
      final container = buildContainer();
      container.read(streamSessionProvider);
      // Let the overridden connectivity stream deliver its first value.
      await Future<void>.delayed(Duration.zero);
      return container;
    }

    test('Wi-Fi only refuses to start on mobile data', () async {
      await addDestination();
      activeNetwork = ActiveNetwork.cellular;
      final container = await startedContainer();
      await container
          .read(networkSettingsProvider.notifier)
          .setPreferredNetwork(PreferredNetwork.wifiOnly);

      await container.read(streamSessionProvider.notifier).startStream();

      verifyNever(() => publisher.start(any()));
      expect(
        container.read(streamSessionProvider).publisherEvent.message,
        contains('Wi-Fi only'),
      );
    });

    test('mobile data is allowed when the policy permits it', () async {
      await addDestination();
      activeNetwork = ActiveNetwork.cellular;
      final container = await startedContainer();
      await container
          .read(networkSettingsProvider.notifier)
          .setPreferredNetwork(PreferredNetwork.cellularAllowed);

      await container.read(streamSessionProvider.notifier).startStream();

      verify(() => publisher.start(any())).called(1);
    });

    test('being offline blocks the start', () async {
      await addDestination();
      activeNetwork = ActiveNetwork.none;
      final container = await startedContainer();

      await container.read(streamSessionProvider.notifier).startStream();

      verifyNever(() => publisher.start(any()));
      expect(
        container.read(streamSessionProvider).publisherEvent.message,
        contains('No network'),
      );
    });

    test('an unknown network does not block the start', () async {
      await addDestination();
      activeNetwork = ActiveNetwork.other;
      final container = await startedContainer();
      await container
          .read(networkSettingsProvider.notifier)
          .setPreferredNetwork(PreferredNetwork.wifiOnly);

      await container.read(streamSessionProvider.notifier).startStream();

      verify(() => publisher.start(any())).called(1);
    });

    test('metered bytes accumulate against the cap and warn at 80%', () async {
      await addDestination();
      activeNetwork = ActiveNetwork.cellular;
      final container = await startedContainer();
      await container
          .read(networkSettingsProvider.notifier)
          .setPreferredNetwork(PreferredNetwork.cellularAllowed);
      await container.read(networkSettingsProvider.notifier).setCellularDataCapMb(1);
      await container.read(streamSessionProvider.notifier).startStream();

      // 0.85 MB of a 1 MB cap.
      publisherEvents.add(
        PublisherEvent(status: PublisherStatus.live, bytesSent: (0.85 * 1024 * 1024).round()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(cellularUsageProvider).bytesSent, greaterThan(0));
      expect(container.read(streamSessionProvider).networkWarning, contains('85%'));
    });

    test('bytes sent over Wi-Fi are not counted against the mobile cap', () async {
      await addDestination();
      final container = await startedContainer();
      await container.read(streamSessionProvider.notifier).startStream();

      publisherEvents.add(
        const PublisherEvent(status: PublisherStatus.live, bytesSent: 5 * 1024 * 1024),
      );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(cellularUsageProvider).bytesSent, 0);
      expect(container.read(streamSessionProvider).networkWarning, isNull);
    });

    test('only forward deltas are counted, so a new session cannot subtract', () async {
      await addDestination();
      activeNetwork = ActiveNetwork.cellular;
      final container = await startedContainer();
      await container
          .read(networkSettingsProvider.notifier)
          .setPreferredNetwork(PreferredNetwork.cellularAllowed);
      await container.read(streamSessionProvider.notifier).startStream();

      publisherEvents.add(const PublisherEvent(status: PublisherStatus.live, bytesSent: 1000));
      await Future<void>.delayed(Duration.zero);
      publisherEvents.add(const PublisherEvent(status: PublisherStatus.live, bytesSent: 1500));
      await Future<void>.delayed(Duration.zero);
      // A fresh session restarts the counter at a lower value.
      publisherEvents.add(const PublisherEvent(status: PublisherStatus.live, bytesSent: 200));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(cellularUsageProvider).bytesSent, 1500);
    });
  });

  group('broadcast target', () {
    test('starts at toServices — the pre-existing default behavior — when nothing is stored', () {
      container = buildContainer();
      expect(container.read(streamSessionProvider).broadcastTarget, BroadcastTarget.toServices);
    });

    test('a stored selection is restored on the next build', () async {
      await BroadcastTargetRepository(settings).write(BroadcastTarget.both);
      container = buildContainer();

      expect(container.read(streamSessionProvider).broadcastTarget, BroadcastTarget.both);
    });

    test('setBroadcastTarget updates state and persists for the next session', () async {
      container = buildContainer();
      container.read(streamSessionProvider);

      await container.read(streamSessionProvider.notifier).setBroadcastTarget(BroadcastTarget.toPc);

      expect(container.read(streamSessionProvider).broadcastTarget, BroadcastTarget.toPc);
      expect(BroadcastTargetRepository(settings).read(), BroadcastTarget.toPc);
    });

    test('toPc with no PC connected reports the specific error and never calls native', () async {
      await addDestination();
      container = buildContainer();
      container.read(streamSessionProvider);
      await container.read(streamSessionProvider.notifier).setBroadcastTarget(BroadcastTarget.toPc);

      await container.read(streamSessionProvider.notifier).startStream();

      verifyNever(() => publisher.start(any()));
      expect(
        container.read(streamSessionProvider).publisherEvent.message,
        // No PC has ever been paired here, which is a different problem
        // from one that is paired but offline -- and needs a different
        // action, so the message says which.
        contains('No PC is paired yet'),
      );
    });

    test('both with no PC connected reports the PC error even though a destination is configured',
        () async {
      await addDestination();
      container = buildContainer();
      container.read(streamSessionProvider);
      await container.read(streamSessionProvider.notifier).setBroadcastTarget(BroadcastTarget.both);

      await container.read(streamSessionProvider.notifier).startStream();

      verifyNever(() => publisher.start(any()));
      expect(
        container.read(streamSessionProvider).publisherEvent.message,
        // No PC has ever been paired here, which is a different problem
        // from one that is paired but offline -- and needs a different
        // action, so the message says which.
        contains('No PC is paired yet'),
      );
    });

    test('toServices with a configured destination publishes and never requests the PC leg',
        () async {
      await addDestination();
      container = buildContainer();
      container.read(streamSessionProvider);
      await container.read(streamSessionProvider.notifier).setBroadcastTarget(BroadcastTarget.toServices);

      await container.read(streamSessionProvider.notifier).startStream();

      final request = verify(() => publisher.start(captureAny())).captured.single as PublishRequest;
      expect(request.legs, hasLength(1));
      expect(request.includePcLeg, isFalse);
      expect(request.pcPeerConnectionId, isNull);
    });

    test('toServices with no destination reports the destinations error', () async {
      container = buildContainer();
      container.read(streamSessionProvider);
      await container.read(streamSessionProvider.notifier).setBroadcastTarget(BroadcastTarget.toServices);

      await container.read(streamSessionProvider.notifier).startStream();

      verifyNever(() => publisher.start(any()));
      expect(
        container.read(streamSessionProvider).publisherEvent.message,
        contains('No enabled destination'),
      );
    });

    // The native publisher supports the PC leg as the only leg as of
    // 2026-08-28 (PublisherForegroundService.start no longer requires an
    // RTMP leg to exist) — these exercise the Dart side of that: a
    // connected PC alone is now a fully valid, non-error request.
    group('PC-only publishing (2026-08-28)', () {
      test('toPc with a connected PC publishes with an empty legs list', () async {
        container = buildContainer();
        container.read(streamSessionProvider);
        await connectMockPc(container);
        await container.read(streamSessionProvider.notifier).setBroadcastTarget(BroadcastTarget.toPc);

        await container.read(streamSessionProvider.notifier).startStream();

        final request = verify(() => publisher.start(captureAny())).captured.single as PublishRequest;
        expect(request.legs, isEmpty);
        expect(request.includePcLeg, isTrue);
        expect(request.pcPeerConnectionId, 'peer-1');
      });

      test('both with a connected PC and a configured destination sends both legs', () async {
        await addDestination();
        container = buildContainer();
        container.read(streamSessionProvider);
        await connectMockPc(container);
        await container.read(streamSessionProvider.notifier).setBroadcastTarget(BroadcastTarget.both);

        await container.read(streamSessionProvider.notifier).startStream();

        final request = verify(() => publisher.start(captureAny())).captured.single as PublishRequest;
        expect(request.legs, hasLength(1));
        expect(request.includePcLeg, isTrue);
        expect(request.pcPeerConnectionId, 'peer-1');
      });

      test('connectToPc surfaces the connected phase via the injected factory', () async {
        container = buildContainer();
        container.read(streamSessionProvider);

        await connectMockPc(container);

        expect(
          container.read(streamSessionProvider).pcConnectionEvent.phase,
          PcConnectionPhase.connected,
        );
        verify(() => pcConnection.connect()).called(1);
      });

      test('toPc still refuses when the connection reports connected but no peer id is available',
          () async {
        when(() => pcConnection.peerConnectionId).thenReturn(null);
        container = buildContainer();
        // Seeded so the scenario is the real one this guard is for: a PC
        // that *is* paired and reports connected, but whose peer connection
        // has gone. Without it the repository would be empty and the error
        // would be the "nothing paired yet" one, which is a different case.
        await container.read(pairedPcsProvider.notifier).addFromPairing(
              pcId: 'pc-1',
              displayName: "Alex's PC",
              host: '192.168.1.42',
              port: 58712,
              wsPath: '/pair',
              token: 'token-1',
            );
        container.read(streamSessionProvider);
        await connectMockPc(container);
        await container.read(streamSessionProvider.notifier).setBroadcastTarget(BroadcastTarget.toPc);

        await container.read(streamSessionProvider.notifier).startStream();

        verifyNever(() => publisher.start(any()));
        expect(
          container.read(streamSessionProvider).publisherEvent.message,
          contains('No PC is connected'),
        );
      });
    });
  });
  group('USB auto-connect', () {
    /// Runs one auto-connect check. The periodic driver lives in
    /// `usbAutoConnectProvider` at the app root (see UsbAutoConnect); these
    /// tests exercise the decision it drives, not the timer.
    Future<void> pumpAutoConnect(ProviderContainer container) async {
      await container
          .read(streamSessionProvider.notifier)
          .maybeAutoConnectOverUsb();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    Future<void> seedPairing(ProviderContainer container) async {
      await container.read(pairedPcsProvider.notifier).addFromPairing(
            pcId: 'pc-1',
            displayName: "Alex's PC",
            host: '192.168.1.42',
            port: 58712,
            wsPath: '/pair',
            token: 'token-1',
          );
    }

    test('the app-root driver kicks off a check as soon as it is built',
        () async {
      // The wiring the other tests in this group deliberately bypass: if
      // nothing builds usbAutoConnectProvider, none of this ever runs.
      final container = buildContainer();
      await seedPairing(container);
      usbDiscovery.pc = const DiscoveredPc(
        pcId: 'pc-1',
        pcName: "Alex's PC",
        host: '127.0.0.1',
        port: 58712,
        wsPath: '/pair',
      );

      container.read(usbAutoConnectProvider);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      verify(() => pcConnection.connect()).called(1);
    });

    test('connects on its own to a paired PC found over the cable', () async {
      // The gap this closes: plugging the cable in used to do nothing at
      // all on the phone, so starting a stream failed with "No PC is
      // connected" while the PC sat there plainly connected.
      final container = buildContainer();
      await seedPairing(container);
      usbDiscovery.pc = const DiscoveredPc(
        pcId: 'pc-1',
        pcName: "Alex's PC",
        host: '127.0.0.1',
        port: 58712,
        wsPath: '/pair',
      );

      await pumpAutoConnect(container);

      verify(() => pcConnection.connect()).called(1);
    });

    test('connects to a PC that has never been paired', () async {
      // The cable is the credential: reaching the phone through its own
      // `adb reverse` tunnel already required the owner to approve that
      // PC's key in Android's USB-debugging prompt. The PC enforces the
      // other half -- it accepts this only from a loopback peer (see the PC
      // client's pairing_server_test).
      final container = buildContainer();
      usbDiscovery.pc = const DiscoveredPc(
        pcId: 'brand-new-pc',
        pcName: 'A PC on the cable',
        host: '127.0.0.1',
        port: 58712,
        wsPath: '/pair',
      );

      await pumpAutoConnect(container);

      verify(() => pcConnection.connect()).called(1);
      final candidate = capturedCandidates.single;
      expect(candidate.authMethod, PairingAuthMethod.usb);
      // Never anything but loopback: a usb hello sent anywhere else is
      // rejected, and sending it would leak the attempt onto the network.
      expect(candidate.hosts, ['127.0.0.1']);
      expect(candidate.token, isNull);
      expect(candidate.pin, isNull);
    });

    test('stores the token the PC mints, so the pairing is visible and revocable',
        () async {
      final container = buildContainer();
      usbDiscovery.pc = const DiscoveredPc(
        pcId: 'brand-new-pc',
        pcName: 'A PC on the cable',
        host: '127.0.0.1',
        port: 58712,
        wsPath: '/pair',
      );
      when(() => pcConnection.issuedToken).thenReturn('minted-by-cable');

      await pumpAutoConnect(container);
      pcConnectionEvents.add(
        const PcConnectionEvent(
          phase: PcConnectionPhase.connected,
          pcId: 'brand-new-pc',
          pcName: 'A PC on the cable',
        ),
      );
      // Storing goes through secure storage and shared preferences, so it
      // takes more than a microtask to land.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      final paired = container.read(pairedPcRepositoryProvider).read();
      expect(paired.map((p) => p.pcId), contains('brand-new-pc'));
    });

    test('does nothing when no cable tunnel is up', () async {
      final container = buildContainer();
      await seedPairing(container);
      usbDiscovery.pc = null;

      await pumpAutoConnect(container);

      verifyNever(() => pcConnection.connect());
    });

    test('respects an explicit disconnect instead of reconnecting', () async {
      // Automation that undoes a deliberate user action is worse than no
      // automation: the Disconnect button would appear not to work.
      final container = buildContainer();
      await seedPairing(container);
      usbDiscovery.pc = const DiscoveredPc(
        pcId: 'pc-1',
        pcName: "Alex's PC",
        host: '127.0.0.1',
        port: 58712,
        wsPath: '/pair',
      );
      await pumpAutoConnect(container);
      verify(() => pcConnection.connect()).called(1);

      await container.read(streamSessionProvider.notifier).disconnectFromPc();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await container.read(streamSessionProvider.notifier).connectToPc(testPairedPc);
      // The only connect after the disconnect is the explicit one.
      verify(() => pcConnection.connect()).called(1);
    });
  });

  group('the "no PC" error explains what is missing', () {
    test('says it is connecting when a PC is on the cable', () async {
      // A cable needs no pairing at all now, so a PC on the tunnel is
      // always moments from being connected -- the auto-connect is already
      // on its way. Telling the user to go and pair it would send them to a
      // screen with nothing to do on it.
      final container = buildContainer();
      usbDiscovery.pc = const DiscoveredPc(
        pcId: 'pc-1',
        pcName: 'DESKTOP-7QRJBCD',
        host: '127.0.0.1',
        port: 58712,
        wsPath: '/pair',
      );
      final notifier = container.read(streamSessionProvider.notifier);
      notifier.setBroadcastTarget(BroadcastTarget.toPc);

      await notifier.startStream();

      final message = container.read(streamSessionProvider).publisherEvent.message;
      expect(message, contains('DESKTOP-7QRJBCD'));
      expect(message, contains('Connecting'));
    });

    test('falls back to the generic message with no cable and no pairing',
        () async {
      final container = buildContainer();
      usbDiscovery.pc = null;
      final notifier = container.read(streamSessionProvider.notifier);
      notifier.setBroadcastTarget(BroadcastTarget.toPc);

      await notifier.startStream();

      final message = container.read(streamSessionProvider).publisherEvent.message;
      expect(message, contains('No PC is paired yet'));
    });
  });

  group('USB is a transport choice, not a race', () {
    Future<void> seedPairing(ProviderContainer container) async {
      await container.read(pairedPcsProvider.notifier).addFromPairing(
            pcId: 'pc-1',
            displayName: "Alex's PC",
            host: '192.168.1.42',
            allHosts: const ['192.168.1.42', '10.0.0.5'],
            port: 58712,
            wsPath: '/pair',
            token: 'token-1',
          );
    }

    test('a cable in use is the only address dialled', () async {
      // The reported bug: the host list used to be [usb, ...lan] and
      // PcSignalingClient races them, so Wi-Fi kept winning. The phone then
      // streamed WebRTC while the compositor's USB source waited forever
      // for an RTMP publisher that was never coming.
      final container = buildContainer();
      await seedPairing(container);
      usbDiscovery.pc = const DiscoveredPc(
        pcId: 'pc-1',
        pcName: "Alex's PC",
        host: '127.0.0.1',
        port: 58712,
        wsPath: '/pair',
      );

      final pc = container.read(pairedPcRepositoryProvider).read().single;
      await container.read(streamSessionProvider.notifier).connectToPc(pc);

      expect(capturedCandidates.single.hosts, ['127.0.0.1']);
    });

    test('the remembered network addresses are used when no cable is up',
        () async {
      final container = buildContainer();
      await seedPairing(container);
      usbDiscovery.pc = null;

      final pc = container.read(pairedPcRepositoryProvider).read().single;
      await container.read(streamSessionProvider.notifier).connectToPc(pc);

      expect(capturedCandidates.single.hosts, contains('192.168.1.42'));
      expect(capturedCandidates.single.hosts, isNot(contains('127.0.0.1')));
    });

    test('turning the preference off keeps the network even with a cable in',
        () async {
      // A phone plugged in to charge must not silently lose the lower
      // latency of the Wi-Fi path.
      final container = buildContainer();
      await seedPairing(container);
      usbDiscovery.pc = const DiscoveredPc(
        pcId: 'pc-1',
        pcName: "Alex's PC",
        host: '127.0.0.1',
        port: 58712,
        wsPath: '/pair',
      );
      await container.read(preferUsbTransportProvider.notifier).set(false);

      final pc = container.read(pairedPcRepositoryProvider).read().single;
      await container.read(streamSessionProvider.notifier).connectToPc(pc);

      expect(capturedCandidates.single.hosts, isNot(contains('127.0.0.1')));
    });

    test('the preference off also stops auto-connecting over the cable',
        () async {
      final container = buildContainer();
      await container.read(preferUsbTransportProvider.notifier).set(false);
      usbDiscovery.pc = const DiscoveredPc(
        pcId: 'pc-1',
        pcName: "Alex's PC",
        host: '127.0.0.1',
        port: 58712,
        wsPath: '/pair',
      );

      await container
          .read(streamSessionProvider.notifier)
          .maybeAutoConnectOverUsb();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      verifyNever(() => pcConnection.connect());
    });

    test('giving up on a session drops it so the transport is re-decided',
        () async {
      // PcConnectionPlatform's candidate is fixed for its lifetime, so a
      // session pinned to the cable would retry loopback forever after the
      // cable was pulled. Dropping it lets the next check pick the network.
      final container = buildContainer();
      await seedPairing(container);
      usbDiscovery.pc = const DiscoveredPc(
        pcId: 'pc-1',
        pcName: "Alex's PC",
        host: '127.0.0.1',
        port: 58712,
        wsPath: '/pair',
      );
      final pc = container.read(pairedPcRepositoryProvider).read().single;
      await container.read(streamSessionProvider.notifier).connectToPc(pc);

      pcConnectionEvents.add(
        const PcConnectionEvent(phase: PcConnectionPhase.disconnected),
      );
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // The session is gone rather than left retrying a dead loopback
      // address, so the transport is decided afresh next time.
      expect(
        container.read(streamSessionProvider).pcConnectionEvent.phase,
        PcConnectionPhase.idle,
      );

      // And with the cable now pulled, that fresh decision is the network.
      usbDiscovery.pc = null;
      await container.read(streamSessionProvider.notifier).connectToPc(pc);
      expect(capturedCandidates.last.hosts, contains('192.168.1.42'));
    });
  });

}
