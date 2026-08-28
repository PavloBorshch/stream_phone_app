import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/audio_settings/domain/audio_settings.dart';
import 'package:stream_phone_cam/features/capture/domain/capture_mode.dart';
import 'package:stream_phone_cam/features/streaming_engine/data/publisher_platform.dart';
import 'package:stream_phone_cam/features/streaming_engine/domain/publish_request.dart';
import 'package:stream_phone_cam/features/streaming_engine/domain/publisher_event.dart';
import 'package:stream_phone_cam/features/video_settings/domain/video_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('com.streamphonecam/publisher');
  final platform = PublisherPlatform();
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? handler;

  setUp(() {
    calls.clear();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (call) async {
        calls.add(call);
        return handler?.call(call);
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      null,
    );
  });

  group('PublisherEvent.fromMap', () {
    test('decodes aggregate stats and per-destination legs', () {
      final event = PublisherEvent.fromMap({
        'status': 'live',
        'bitrateKbps': 4200,
        'fps': 30,
        'droppedFrames': 12,
        'uptimeSeconds': 95,
        'destinations': [
          {'destinationId': 'a', 'status': 'live', 'targetBitrateKbps': 2500, 'rttMs': 40},
          {'destinationId': 'b', 'status': 'reconnecting', 'message': 'socket closed'},
        ],
      });

      expect(event.status, PublisherStatus.live);
      expect(event.bitrateKbps, 4200);
      expect(event.destinations, hasLength(2));
      expect(event.destinations.first.targetBitrateKbps, 2500);
      expect(event.destinations.first.rttMs, 40);
      expect(event.destinations.last.status, PublisherStatus.reconnecting);
      expect(event.destinations.last.message, 'socket closed');
    });

    test('an unknown status decodes as idle rather than throwing', () {
      expect(PublisherEvent.fromMap({'status': 'buffering'}).status, PublisherStatus.idle);
    });

    test('isActive covers a mid-stream reconnect', () {
      expect(const PublisherEvent(status: PublisherStatus.reconnecting).isActive, isTrue);
      expect(const PublisherEvent(status: PublisherStatus.connecting).isActive, isTrue);
      expect(const PublisherEvent(status: PublisherStatus.stopped).isActive, isFalse);
      expect(PublisherEvent.idle.isActive, isFalse);
    });
  });

  group('PublisherPlatform', () {
    test('start() sends the flattened request over the method channel', () async {
      const video = VideoSettings(
        resolution: VideoResolution.p720,
        frameRate: VideoFrameRate.fps60,
        codec: VideoCodec.hevc,
        bitrateKbps: 4500,
        adaptiveBitrate: true,
      );

      await platform.start(
        const PublishRequest(
          source: CaptureMode.camera,
          video: video,
          audio: AudioSettings.defaults,
          legs: [
            PublishLeg(
              destinationId: 'dest-1',
              displayName: 'My RTMP',
              url: 'rtmp://example.com/live',
              streamKey: 'secret',
              video: video,
            ),
          ],
          includePcLeg: true,
          pcPeerConnectionId: 'pc-1',
        ),
      );

      expect(calls.single.method, 'start');
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['source'], 'camera');
      expect(arguments['includePcLeg'], true);
      expect(arguments['pcPeerConnectionId'], 'pc-1');
      expect((arguments['video']! as Map<Object?, Object?>)['width'], 1280);
      expect((arguments['video']! as Map<Object?, Object?>)['fps'], 60);
      expect((arguments['audio']! as Map<Object?, Object?>)['sampleRate'], 48000);
      final legs = arguments['legs']! as List<Object?>;
      expect((legs.single! as Map<Object?, Object?>)['streamKey'], 'secret');
    });

    test('pcPeerConnectionId defaults to null when Leg A is not attempted', () async {
      await platform.start(
        const PublishRequest(
          source: CaptureMode.camera,
          video: VideoSettings.defaults,
          audio: AudioSettings.defaults,
          legs: [],
          includePcLeg: false,
        ),
      );

      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['includePcLeg'], false);
      expect(arguments['pcPeerConnectionId'], isNull);
    });

    test('supportedCodecs() maps native names and ignores ones this app has no enum for',
        () async {
      handler = (call) => call.method == 'supportedCodecs' ? ['h264', 'hevc', 'vp9'] : null;

      expect(await platform.supportedCodecs(), {VideoCodec.h264, VideoCodec.hevc});
    });

    test('supportedCodecs() falls back to H.264 when native reports nothing usable', () async {
      handler = (call) => call.method == 'supportedCodecs' ? <String>[] : null;

      expect(await platform.supportedCodecs(), {VideoCodec.fallback});
    });

    test('getStatus() returns idle when native has no session', () async {
      handler = (call) => null;

      expect((await platform.getStatus()).status, PublisherStatus.idle);
    });

    test('setMuted() forwards the flag', () async {
      await platform.setMuted(true);

      expect(calls.single.method, 'setMuted');
      expect((calls.single.arguments as Map<Object?, Object?>)['muted'], true);
    });
  });
}
