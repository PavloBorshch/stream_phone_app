import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_phone_cam/features/camera/data/camera_capture_platform.dart';
import 'package:stream_phone_cam/features/camera/domain/camera_capture_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('com.streamphonecam/camera');
  final platform = CameraCapturePlatform();
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

  group('CameraCaptureEvent.fromMap', () {
    test('decodes a running preview', () {
      final event = CameraCaptureEvent.fromMap({
        'status': 'running',
        'textureId': 3,
        'width': 1920,
        'height': 1080,
        'lensFacingFront': true,
        'hasMultipleCameras': true,
      });

      expect(event.status, CameraCaptureStatus.running);
      expect(event.isPreviewReady, isTrue);
      expect(event.textureId, 3);
      expect(event.lensFacingFront, isTrue);
    });

    test('running without a texture is not previewable yet', () {
      // The native side reports "running" as soon as the mixer starts, which
      // can precede a texture being registered for this engine.
      final event = CameraCaptureEvent.fromMap({'status': 'running'});

      expect(event.status, CameraCaptureStatus.running);
      expect(event.isPreviewReady, isFalse);
    });

    test('an unknown status decodes as idle rather than throwing', () {
      expect(CameraCaptureEvent.fromMap({'status': 'warming-up'}).status, CameraCaptureStatus.idle);
    });

    test('missing flags default to false rather than null', () {
      final event = CameraCaptureEvent.fromMap({'status': 'idle'});

      expect(event.lensFacingFront, isFalse);
      expect(event.hasMultipleCameras, isFalse);
    });
  });

  group('CameraCapturePlatform', () {
    test('startPreview() sends the capture size and omits an unspecified lens', () async {
      handler = (call) => 7;

      final textureId = await platform.startPreview(width: 1280, height: 720);

      expect(textureId, 7);
      expect(calls.single.method, 'startPreview');
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['width'], 1280);
      expect(arguments['height'], 720);
      // Leaving the lens out means "keep whichever camera is already open" —
      // sending an explicit default would silently flip the user's choice back
      // on every re-attach.
      expect(arguments.containsKey('front'), isFalse);
    });

    test('startPreview() forwards an explicit lens choice', () async {
      handler = (call) => 7;

      await platform.startPreview(width: 1280, height: 720, front: true);

      expect((calls.single.arguments as Map<Object?, Object?>)['front'], true);
    });

    test('switchCamera() carries the size so the new lens opens at capture resolution', () async {
      handler = (call) => 9;

      final textureId = await platform.switchCamera(width: 1920, height: 1080);

      expect(textureId, 9);
      expect(calls.single.method, 'switchCamera');
      expect((calls.single.arguments as Map<Object?, Object?>)['height'], 1080);
    });

    test('getStatus() returns idle when native has no session', () async {
      handler = (call) => null;

      expect((await platform.getStatus()).status, CameraCaptureStatus.idle);
    });

    test('stopPreview() takes no arguments — the native side decides', () async {
      await platform.stopPreview();

      expect(calls.single.method, 'stopPreview');
      expect(calls.single.arguments, isNull);
    });
  });
}
