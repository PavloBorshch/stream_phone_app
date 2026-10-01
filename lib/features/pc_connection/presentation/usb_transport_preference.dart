import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/settings_repository_provider.dart';

/// Whether the phone should send to the PC over the USB cable when one is
/// available, instead of over the network.
///
/// This has to be a choice rather than a rule, because neither transport is
/// simply better:
///
/// * **USB** works with every radio off, and is unaffected by a congested
///   or absent Wi-Fi network.
/// * **Wi-Fi** is *lower latency*. The cable carries media as RTMP (WebRTC
///   cannot cross an `adb reverse` tunnel), and RTMP's buffering plus a GOP
///   costs noticeably more delay than the WebRTC path.
///
/// And crucially, "a cable is plugged in" does not imply "use the cable":
/// in this app the phone is very often plugged in simply to charge while
/// streaming. Choosing the transport by whether a cable happens to be
/// present would silently trade latency away every time someone charged
/// their phone.
///
/// Defaults to preferring USB: someone who has set up USB debugging and
/// plugged the phone into the machine running the PC client has gone to
/// deliberate trouble to make that link exist, and the reliability is
/// usually what they were after.
class PreferUsbTransportNotifier extends Notifier<bool> {
  static const _key = 'prefer_usb_transport';

  @override
  bool build() {
    final json = ref.watch(settingsRepositoryProvider).readJson(_key);
    return json?['enabled'] as bool? ?? true;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    await ref
        .read(settingsRepositoryProvider)
        .writeJson(_key, {'enabled': enabled});
  }
}

final preferUsbTransportProvider =
    NotifierProvider<PreferUsbTransportNotifier, bool>(
      PreferUsbTransportNotifier.new,
    );
