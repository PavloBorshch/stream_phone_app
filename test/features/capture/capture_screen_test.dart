import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/secure_token_store.dart';
import 'package:stream_phone_cam/core/persistence/secure_token_store_provider.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository_provider.dart';
import 'package:stream_phone_cam/core/session/stream_session_provider.dart';
import 'package:stream_phone_cam/features/camera/data/camera_capture_platform.dart';
import 'package:stream_phone_cam/features/camera/domain/camera_capture_status.dart';
import 'package:stream_phone_cam/features/camera/presentation/camera_preview_pane.dart';
import 'package:stream_phone_cam/features/battery_performance/data/battery_service.dart';
import 'package:stream_phone_cam/features/battery_performance/domain/device_health.dart';
import 'package:stream_phone_cam/features/battery_performance/presentation/battery_performance_provider.dart';
import 'package:stream_phone_cam/features/capture/domain/capture_mode.dart';
import 'package:stream_phone_cam/features/capture/presentation/capture_screen.dart';
import 'package:stream_phone_cam/features/destinations/data/destinations_repository.dart';
import 'package:stream_phone_cam/features/destinations/domain/stream_destination.dart';
import 'package:stream_phone_cam/features/overlays/presentation/stream_stats_overlay.dart';
import 'package:stream_phone_cam/features/network_settings/domain/active_network.dart';
import 'package:stream_phone_cam/features/network_settings/domain/network_settings.dart';
import 'package:stream_phone_cam/features/network_settings/presentation/network_settings_provider.dart';
import 'package:stream_phone_cam/features/screencast/data/screencast_platform.dart';
import 'package:stream_phone_cam/features/screencast/domain/screencast_status.dart';
import 'package:stream_phone_cam/features/streaming_engine/data/publisher_platform.dart';
import 'package:stream_phone_cam/features/streaming_engine/domain/publish_request.dart';
import 'package:stream_phone_cam/features/streaming_engine/domain/publisher_event.dart';
import 'package:stream_phone_cam/features/streaming_engine/presentation/publisher_provider.dart';

class MockScreencastPlatform extends Mock implements ScreencastPlatform {}

class MockPublisherPlatform extends Mock implements PublisherPlatform {}

class MockCameraCapturePlatform extends Mock implements CameraCapturePlatform {}

class MockSecureTokenStore extends Mock implements SecureTokenStore {}

class _FakePublishRequest extends Fake implements PublishRequest {}

void main() {
  late MockScreencastPlatform screencast;
  late MockPublisherPlatform publisher;
  late MockCameraCapturePlatform camera;
  late MockSecureTokenStore secureStore;
  late SettingsRepository settings;
  late StreamController<PublisherEvent> publisherEvents;
  late StreamController<ScreencastEvent> screencastEvents;
  late ActiveNetwork activeNetwork;
  late BatteryStatus batteryStatus;
  late ThermalStatus thermalStatus;

  setUpAll(() => registerFallbackValue(_FakePublishRequest()));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsRepository.create();
    activeNetwork = ActiveNetwork.wifi;
    batteryStatus = BatteryStatus.unknown;
    thermalStatus = ThermalStatus.none;

    publisherEvents = StreamController<PublisherEvent>.broadcast();
    screencastEvents = StreamController<ScreencastEvent>.broadcast();
    addTearDown(publisherEvents.close);
    addTearDown(screencastEvents.close);

    screencast = MockScreencastPlatform();
    when(() => screencast.events()).thenAnswer((_) => screencastEvents.stream);
    when(() => screencast.getStatus()).thenAnswer((_) async => ScreencastEvent.idle);
    when(() => screencast.requestCapture()).thenAnswer((_) async {});
    when(() => screencast.stopCapture()).thenAnswer((_) async {});

    publisher = MockPublisherPlatform();
    when(() => publisher.events()).thenAnswer((_) => publisherEvents.stream);
    when(() => publisher.getStatus()).thenAnswer((_) async => PublisherEvent.idle);
    when(() => publisher.start(any())).thenAnswer((_) async {});
    when(() => publisher.stop()).thenAnswer((_) async {});
    when(() => publisher.setMuted(any())).thenAnswer((_) async {});
    when(
      () => publisher.setQualityCeiling(
        scale: any(named: 'scale'),
        frameRateCap: any(named: 'frameRateCap'),
      ),
    ).thenAnswer((_) async {});

    camera = MockCameraCapturePlatform();
    when(() => camera.events()).thenAnswer((_) => const Stream<CameraCaptureEvent>.empty());
    when(() => camera.getStatus()).thenAnswer((_) async => CameraCaptureEvent.idle);
    when(
      () => camera.startPreview(
        width: any(named: 'width'),
        height: any(named: 'height'),
        front: any(named: 'front'),
      ),
    ).thenAnswer((_) async => 1);
    when(() => camera.stopPreview()).thenAnswer((_) async {});

    secureStore = MockSecureTokenStore();
    when(() => secureStore.write(any(), any())).thenAnswer((_) async {});
    when(() => secureStore.delete(any())).thenAnswer((_) async {});
    when(() => secureStore.read(any())).thenAnswer((_) async => 'stream-key');
  });

  Future<void> addDestination() async {
    await DestinationsRepository(settings, secureStore).add(
      platform: StreamPlatform.custom,
      displayName: 'My RTMP',
      rtmpUrl: 'rtmp://example.com/live',
      streamKey: 'stream-key',
    );
  }

  Future<ProviderContainer> pumpCaptureScreen(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        screencastPlatformProvider.overrideWithValue(screencast),
        publisherPlatformProvider.overrideWithValue(publisher),
        cameraCapturePlatformProvider.overrideWithValue(camera),
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
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CaptureScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('idle camera mode shows the ready pill and a record icon', (tester) async {
    await pumpCaptureScreen(tester);

    expect(find.text('CAMERA | READY'), findsOneWidget);
    expect(find.byIcon(Icons.videocam), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
  });

  testWidgets('tapping record publishes to the configured destinations', (tester) async {
    await addDestination();
    await pumpCaptureScreen(tester);

    await tester.tap(find.byIcon(Icons.videocam));
    await tester.pump();

    verify(() => publisher.start(any())).called(1);
  });

  testWidgets('a live session shows real stats in the status pill', (tester) async {
    await pumpCaptureScreen(tester);

    publisherEvents.add(
      const PublisherEvent(
        status: PublisherStatus.live,
        bitrateKbps: 4500,
        fps: 30,
        droppedFrames: 7,
      ),
    );
    await tester.pump();

    expect(find.text('LIVE | 4500 kbps | 30 fps | 7 dropped'), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('dropped frames are omitted while none have been dropped', (tester) async {
    await pumpCaptureScreen(tester);

    publisherEvents.add(
      const PublisherEvent(
        status: PublisherStatus.live,
        bitrateKbps: 4500,
        fps: 30,
        droppedFrames: 0,
      ),
    );
    await tester.pump();

    expect(find.text('LIVE | 4500 kbps | 30 fps'), findsOneWidget);
  });

  testWidgets('a mid-stream reconnect still reads as streaming', (tester) async {
    await pumpCaptureScreen(tester);

    publisherEvents.add(const PublisherEvent(status: PublisherStatus.reconnecting));
    await tester.pump();

    expect(find.text('RECONNECTING'), findsOneWidget);
    // The encoder is still running, so the button must offer "stop", not a
    // second "start".
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('tapping stop while live stops the publisher', (tester) async {
    await pumpCaptureScreen(tester);
    publisherEvents.add(const PublisherEvent(status: PublisherStatus.live));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    verify(() => publisher.stop()).called(1);
  });

  testWidgets('a publisher error surfaces its message in a snack bar', (tester) async {
    await pumpCaptureScreen(tester);

    publisherEvents.add(
      const PublisherEvent(
        status: PublisherStatus.error,
        message: 'SRT is not supported on Android yet.',
      ),
    );
    await tester.pump();

    expect(find.text('ERROR'), findsOneWidget);
    expect(find.text('SRT is not supported on Android yet.'), findsOneWidget);
  });

  testWidgets('starting with no destination reports why, without calling native', (tester) async {
    await pumpCaptureScreen(tester);

    await tester.tap(find.byIcon(Icons.videocam));
    await tester.pump();

    verifyNever(() => publisher.start(any()));
    expect(find.textContaining('No enabled destination'), findsOneWidget);
  });

  group('screencast mode', () {
    Future<ProviderContainer> pumpInScreencastMode(WidgetTester tester) async {
      final container = await pumpCaptureScreen(tester);
      container.read(streamSessionProvider.notifier).setMode(CaptureMode.screencast);
      await tester.pump();
      return container;
    }

    testWidgets('a capture that is running but not streaming offers a stop-capture control',
        (tester) async {
      await pumpInScreencastMode(tester);

      screencastEvents.add(const ScreencastEvent(status: ScreencastStatus.capturing));
      await tester.pump();

      expect(find.byIcon(Icons.stop_screen_share), findsOneWidget);
      await tester.tap(find.byIcon(Icons.stop_screen_share));
      await tester.pump();
      verify(() => screencast.stopCapture()).called(1);
    });

    testWidgets('the stop-capture control disappears once the stream is live', (tester) async {
      await pumpInScreencastMode(tester);
      screencastEvents.add(const ScreencastEvent(status: ScreencastStatus.capturing));
      await tester.pump();

      publisherEvents.add(const PublisherEvent(status: PublisherStatus.live));
      await tester.pump();

      expect(find.byIcon(Icons.stop_screen_share), findsNothing);
    });

    testWidgets('stopping a screencast stream also ends the projection', (tester) async {
      await pumpInScreencastMode(tester);
      screencastEvents.add(const ScreencastEvent(status: ScreencastStatus.capturing));
      publisherEvents.add(const PublisherEvent(status: PublisherStatus.live));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();

      verify(() => publisher.stop()).called(1);
      verify(() => screencast.stopCapture()).called(1);
    });

    testWidgets('switching to Camera stops a running-but-not-streaming capture', (tester) async {
      final container = await pumpInScreencastMode(tester);
      screencastEvents.add(const ScreencastEvent(status: ScreencastStatus.capturing));
      await tester.pump();

      await tester.tap(find.text('Camera'));
      await tester.pump();

      verify(() => screencast.stopCapture()).called(1);
      verifyNever(() => publisher.stop());
      expect(container.read(streamSessionProvider).mode, CaptureMode.camera);
    });

    testWidgets('switching to Camera while live stops both the stream and the projection',
        (tester) async {
      final container = await pumpInScreencastMode(tester);
      screencastEvents.add(const ScreencastEvent(status: ScreencastStatus.capturing));
      publisherEvents.add(const PublisherEvent(status: PublisherStatus.live));
      await tester.pump();

      await tester.tap(find.text('Camera'));
      await tester.pump();

      verify(() => publisher.stop()).called(1);
      verify(() => screencast.stopCapture()).called(1);
      expect(container.read(streamSessionProvider).mode, CaptureMode.camera);
    });

    testWidgets('switching away from a paused capture stops it too', (tester) async {
      await pumpInScreencastMode(tester);
      screencastEvents.add(const ScreencastEvent(status: ScreencastStatus.paused));
      await tester.pump();

      await tester.tap(find.text('Camera'));
      await tester.pump();

      verify(() => screencast.stopCapture()).called(1);
    });
  });

  testWidgets('switching to Screencast while a camera stream is live stops it first',
      (tester) async {
    final container = await pumpCaptureScreen(tester);
    publisherEvents.add(const PublisherEvent(status: PublisherStatus.live));
    await tester.pump();

    await tester.tap(find.text('Screencast'));
    await tester.pump();

    verify(() => publisher.stop()).called(1);
    verifyNever(() => screencast.stopCapture());
    expect(container.read(streamSessionProvider).mode, CaptureMode.screencast);
  });

  testWidgets('a mobile-data cap warning is shown, and shown only once', (tester) async {
    await addDestination();
    activeNetwork = ActiveNetwork.cellular;
    final container = await pumpCaptureScreen(tester);
    await container
        .read(networkSettingsProvider.notifier)
        .setPreferredNetwork(PreferredNetwork.cellularAllowed);
    await container.read(networkSettingsProvider.notifier).setCellularDataCapMb(1);

    await tester.tap(find.byIcon(Icons.videocam));
    await tester.pump();

    publisherEvents.add(
      PublisherEvent(status: PublisherStatus.live, bytesSent: (0.85 * 1024 * 1024).round()),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('85%'), findsOneWidget);

    // The stats tick repeats every second; the same warning must not stack up
    // a new snack bar each time.
    publisherEvents.add(
      PublisherEvent(status: PublisherStatus.live, bytesSent: (0.86 * 1024 * 1024).round()),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('85%'), findsOneWidget);
  });

  group('overlays', () {
    testWidgets('the mute button toggles the mic without stopping the stream', (tester) async {
      final container = await pumpCaptureScreen(tester);
      publisherEvents.add(const PublisherEvent(status: PublisherStatus.live));
      await tester.pump();

      expect(find.byIcon(Icons.mic), findsOneWidget);
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      verify(() => publisher.setMuted(true)).called(1);
      verifyNever(() => publisher.stop());
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(container.read(streamSessionProvider).isMuted, isTrue);

      await tester.tap(find.byIcon(Icons.mic_off));
      await tester.pump();
      verify(() => publisher.setMuted(false)).called(1);
    });

    testWidgets('the stats overlay only appears while a session is active', (tester) async {
      await pumpCaptureScreen(tester);
      expect(find.byType(StreamStatsOverlay), findsOneWidget);
      expect(find.byIcon(Icons.insights), findsNothing);

      publisherEvents.add(
        const PublisherEvent(
          status: PublisherStatus.live,
          bitrateKbps: 3800,
          targetBitrateKbps: 4500,
          bytesSent: 5 * 1024 * 1024,
          uptimeSeconds: 65,
          destinations: [
            DestinationPublishState(destinationId: 'a', status: PublisherStatus.live),
            DestinationPublishState(destinationId: 'b', status: PublisherStatus.error),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('1/2 live'), findsOneWidget);
    });

    testWidgets('expanding the overlay shows measured against target', (tester) async {
      await pumpCaptureScreen(tester);
      publisherEvents.add(
        const PublisherEvent(
          status: PublisherStatus.live,
          bitrateKbps: 3800,
          targetBitrateKbps: 4500,
          bytesSent: 5 * 1024 * 1024,
          uptimeSeconds: 65,
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.insights));
      await tester.pump();

      // The pair is what explains a quality drop; either number alone doesn't.
      expect(find.text('3800 kbps of 4500'), findsOneWidget);
      expect(find.text('01:05'), findsOneWidget);
      expect(find.text('5.0 MB'), findsOneWidget);
    });
  });
}
