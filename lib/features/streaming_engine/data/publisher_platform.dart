import 'package:flutter/services.dart';

import '../../video_settings/domain/video_settings.dart';
import '../domain/publish_request.dart';
import '../domain/publisher_event.dart';

/// Dart side of the native RTMP/RTMPS/SRT publisher (PLAN.md Phase 5),
/// following the same one-MethodChannel-plus-one-EventChannel shape as
/// `ScreencastPlatform`: imperative calls on the method channel, a
/// continuous typed status/stats stream on the event channel, and a one-shot
/// [getStatus] to cover the race where native state predates the Dart
/// subscription (the publisher outlives the Flutter engine on Android — it
/// runs in `PublisherForegroundService`).
class PublisherPlatform {
  static const MethodChannel _methodChannel = MethodChannel('com.streamphonecam/publisher');
  static const EventChannel _eventChannel = EventChannel('com.streamphonecam/publisher_events');

  Future<void> start(PublishRequest request) {
    return _methodChannel.invokeMethod('start', request.toMap());
  }

  Future<void> stop() => _methodChannel.invokeMethod('stop');

  /// Drops/restores the mic input without interrupting the session — the
  /// encoder keeps producing silent audio frames so the ingest never sees a
  /// gap in the audio track (Phase 7's quick mute toggle wires into this).
  Future<void> setMuted(bool muted) {
    return _methodChannel.invokeMethod('setMuted', {'muted': muted});
  }

  /// Caps quality on behalf of the battery/thermal guards (PLAN.md Phase 7).
  /// [scale] is a fraction of the configured bitrate and [frameRateCap] is a
  /// frame-rate ceiling (0 for none). Kept separate from the network
  /// adaptation the publisher does on its own, so lifting a guard restores
  /// whatever the network had independently settled on.
  Future<void> setQualityCeiling({required double scale, required int frameRateCap}) {
    return _methodChannel.invokeMethod('setQualityCeiling', {
      'scale': scale,
      'frameRateCap': frameRateCap,
    });
  }

  Future<PublisherEvent> getStatus() async {
    final raw = await _methodChannel.invokeMapMethod<String, dynamic>('getStatus');
    if (raw == null) return PublisherEvent.idle;
    return PublisherEvent.fromMap(raw);
  }

  /// Video codecs this device actually has a hardware encoder for, queried
  /// natively (`MediaCodecList` / `VTCopyVideoEncoderList`). AV1 encode
  /// exists only on a few recent SoCs, so the Video Settings screen offers
  /// only what comes back here and falls back to [VideoCodec.fallback]
  /// otherwise (PLAN.md §1.5).
  Future<Set<VideoCodec>> supportedCodecs() async {
    final raw = await _methodChannel.invokeListMethod<String>('supportedCodecs');
    if (raw == null || raw.isEmpty) return {VideoCodec.fallback};
    final codecs = raw
        .map((name) => VideoCodec.values.where((codec) => codec.name == name))
        .expand((matches) => matches)
        .toSet();
    return codecs.isEmpty ? {VideoCodec.fallback} : codecs;
  }

  Stream<PublisherEvent> events() {
    return _eventChannel.receiveBroadcastStream().map(
      (raw) => PublisherEvent.fromMap(Map<String, dynamic>.from(raw as Map)),
    );
  }
}
