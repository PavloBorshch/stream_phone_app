import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stream_phone_cam/core/session/stream_session_provider.dart';
import 'package:stream_phone_cam/features/capture/domain/capture_mode.dart';
import 'package:stream_phone_cam/features/screencast/data/screencast_platform.dart';
import 'package:stream_phone_cam/features/screencast/domain/screencast_status.dart';

class MockScreencastPlatform extends Mock implements ScreencastPlatform {}

void main() {
  late MockScreencastPlatform platform;
  late ProviderContainer container;

  ProviderContainer buildContainer() {
    final c = ProviderContainer(
      overrides: [screencastPlatformProvider.overrideWithValue(platform)],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    platform = MockScreencastPlatform();
    when(() => platform.events()).thenAnswer((_) => const Stream.empty());
    when(() => platform.getStatus()).thenAnswer((_) async => ScreencastEvent.idle);
  });

  test('starts in camera mode with an idle screencast event', () {
    container = buildContainer();
    final state = container.read(streamSessionProvider);
    expect(state.mode, CaptureMode.camera);
    expect(state.screencastEvent.status, ScreencastStatus.idle);
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
}
