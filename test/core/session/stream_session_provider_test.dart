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
import 'package:stream_phone_cam/features/capture/domain/capture_mode.dart';
import 'package:stream_phone_cam/features/destinations/data/destinations_repository.dart';
import 'package:stream_phone_cam/features/destinations/domain/stream_destination.dart';
import 'package:stream_phone_cam/features/network_settings/domain/active_network.dart';
import 'package:stream_phone_cam/features/network_settings/domain/network_settings.dart';
import 'package:stream_phone_cam/features/network_settings/presentation/network_settings_provider.dart';
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

class _FakePublishRequest extends Fake implements PublishRequest {}

void main() {
  late MockScreencastPlatform platform;
  late MockPublisherPlatform publisher;
  late MockSecureTokenStore secureStore;
  late SettingsRepository settings;
  late ProviderContainer container;
  late StreamController<PublisherEvent> publisherEvents;

  setUpAll(() {
    registerFallbackValue(_FakePublishRequest());
  });

  /// The network the fake connectivity layer reports. Defaults to Wi-Fi so
  /// policy never blocks the tests that aren't about policy.
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
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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
  });

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

  test('a connected PC alone is not yet a publishable destination', () async {
    // Leg A (WebRTC to the PC) has no path into the native capture pipeline
    // yet, so it must not be silently counted as a destination — the user
    // would get a "connecting" that never becomes live.
    container = buildContainer();
    container.read(streamSessionProvider);

    await container.read(streamSessionProvider.notifier).startStream();

    verifyNever(() => publisher.start(any()));
    expect(
      container.read(streamSessionProvider).publisherEvent.status,
      PublisherStatus.error,
    );
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
}
