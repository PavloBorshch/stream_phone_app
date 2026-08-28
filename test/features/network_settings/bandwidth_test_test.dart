import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stream_phone_cam/features/audio_settings/domain/audio_settings.dart';
import 'package:stream_phone_cam/features/destinations/domain/stream_destination.dart';
import 'package:stream_phone_cam/features/network_settings/data/bandwidth_test.dart';
import 'package:stream_phone_cam/features/network_settings/domain/bandwidth_test_result.dart';
import 'package:stream_phone_cam/features/streaming_engine/data/publisher_platform.dart';
import 'package:stream_phone_cam/features/streaming_engine/domain/publish_request.dart';
import 'package:stream_phone_cam/features/streaming_engine/domain/publisher_event.dart';
import 'package:stream_phone_cam/features/video_settings/domain/video_settings.dart';

class MockPublisherPlatform extends Mock implements PublisherPlatform {}

class _FakePublishRequest extends Fake implements PublishRequest {}

/// The real 8 seconds is a product decision, not something worth spending in
/// every test run.
const _fast = Duration(milliseconds: 20);

const _destination = StreamDestination(
  id: 'dest-1',
  platform: StreamPlatform.custom,
  displayName: 'My RTMP',
  rtmpUrl: 'rtmp://example.com/live',
  secureKeyId: 'key-1',
  enabled: true,
);

void main() {
  setUpAll(() => registerFallbackValue(_FakePublishRequest()));

  group('BandwidthTestResult.evaluate', () {
    test('keeps headroom rather than recommending the measured rate', () {
      final result = BandwidthTestResult.evaluate(
        achievedKbps: 5000,
        targetKbps: 9000,
        current: VideoSettings.defaults,
      );

      // A link measured at 5000 must not be handed a 5000 kbps target.
      expect(result.usableKbps, 4000);
      expect(result.recommended!.bitrateKbps, lessThanOrEqualTo(4000));
    });

    test('recommends the largest preset that fits', () {
      final result = BandwidthTestResult.evaluate(
        achievedKbps: 4000,
        targetKbps: 9000,
        current: VideoSettings.defaults,
      );

      final recommended = result.recommended!;
      expect(recommended.bitrateKbps, lessThanOrEqualTo(result.usableKbps));
      // 3200 usable comfortably covers 720p30 (3000) but not 1080p30 (4500).
      expect(recommended.resolution, VideoResolution.p720);
    });

    test('a link that meets its target needs no change', () {
      final result = BandwidthTestResult.evaluate(
        achievedKbps: 9000,
        targetKbps: 9000,
        current: VideoSettings.defaults,
      );

      expect(result.meetsTarget, isTrue);
      expect(result.fractionOfTarget, 1.0);
    });

    test('a hopeless link recommends nothing rather than an unusable preset', () {
      final result = BandwidthTestResult.evaluate(
        achievedKbps: 200,
        targetKbps: 4500,
        current: VideoSettings.defaults,
      );

      expect(result.recommended, isNull);
      expect(result.meetsTarget, isFalse);
    });

    test('the recommendation keeps the codec and adaptive setting', () {
      const current = VideoSettings(
        resolution: VideoResolution.p2160,
        frameRate: VideoFrameRate.fps60,
        codec: VideoCodec.hevc,
        bitrateKbps: 25000,
        adaptiveBitrate: false,
      );

      final result = BandwidthTestResult.evaluate(
        achievedKbps: 4000,
        targetKbps: 25000,
        current: current,
      );

      expect(result.recommended!.codec, VideoCodec.hevc);
      expect(result.recommended!.adaptiveBitrate, isFalse);
    });
  });

  group('BandwidthTest.run', () {
    late MockPublisherPlatform publisher;
    late StreamController<PublisherEvent> events;

    setUp(() {
      publisher = MockPublisherPlatform();
      events = StreamController<PublisherEvent>.broadcast();
      addTearDown(events.close);
      when(() => publisher.events()).thenAnswer((_) => events.stream);
      when(() => publisher.start(any())).thenAnswer((_) async {});
      when(() => publisher.stop()).thenAnswer((_) async {});
    });

    Future<BandwidthTestResult> runWith(List<int> samples) async {
      final future = BandwidthTest(publisher, duration: _fast).run(
        destination: _destination,
        streamKey: 'secret',
        video: VideoSettings.defaults,
        audio: AudioSettings.defaults,
      );
      // Feed samples while the test's own timer is pending.
      await Future<void>.delayed(Duration.zero);
      for (final sample in samples) {
        events.add(PublisherEvent(status: PublisherStatus.live, bitrateKbps: sample));
      }
      await Future<void>.delayed(Duration.zero);
      return future;
    }

    test('disables adaptation for the run so it measures the link, not itself', () async {
      unawaited(runWith(const [4000, 4000, 4000, 4000, 4000, 4000]));
      await Future<void>.delayed(Duration.zero);

      final request = verify(() => publisher.start(captureAny())).captured.single as PublishRequest;
      expect(request.video.adaptiveBitrate, isFalse);
      expect(request.legs.single.streamKey, 'secret');
      expect(request.includePcLeg, isFalse);
      events.add(const PublisherEvent(status: PublisherStatus.live, bitrateKbps: 1));
    });

    test('discards warm-up samples and takes the median of the rest', () async {
      // The first three are the handshake and encoder ramp; a mean over all of
      // them would understate the link badly.
      final result = await runWith(const [10, 20, 30, 4000, 4200, 4100]);

      expect(result.achievedKbps, 4100);
    });

    test('always stops publishing, even when nothing was measured', () async {
      await expectLater(
        runWith(const []),
        throwsA(isA<BandwidthTestException>()),
      );

      verify(() => publisher.stop()).called(1);
    });

    test('stops publishing if starting throws', () async {
      when(() => publisher.start(any())).thenThrow(Exception('refused'));

      await expectLater(
        BandwidthTest(publisher, duration: _fast).run(
          destination: _destination,
          streamKey: 'secret',
          video: VideoSettings.defaults,
          audio: AudioSettings.defaults,
        ),
        throwsA(isA<Exception>()),
      );

      // The user must never be left unknowingly broadcasting.
      verify(() => publisher.stop()).called(1);
    });
  });
}
