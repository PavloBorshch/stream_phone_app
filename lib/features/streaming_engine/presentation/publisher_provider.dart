import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../video_settings/domain/video_settings.dart';
import '../data/publisher_platform.dart';

final publisherPlatformProvider = Provider<PublisherPlatform>((ref) => PublisherPlatform());

/// Codecs the Video Settings screen may offer on this device.
///
/// Degrades to just [VideoCodec.fallback] rather than surfacing an error if
/// the native publisher isn't reachable — that is the expected case in
/// widget tests and on a platform where the Phase 5 native side isn't built
/// yet, and H.264 is a truthful answer for any device that can encode at all.
final supportedVideoCodecsProvider = FutureProvider<Set<VideoCodec>>((ref) async {
  try {
    return await ref.watch(publisherPlatformProvider).supportedCodecs();
  } on MissingPluginException {
    return {VideoCodec.fallback};
  } on PlatformException catch (error) {
    debugPrint('supportedCodecs query failed: $error');
    return {VideoCodec.fallback};
  }
});
