import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/stream_session_provider.dart';

/// Watches the USB cable and connects to whatever PC is on the other end.
///
/// Polled, because nothing pushes "a cable was plugged in" to this process
/// and Dart exposes no interface-change notification. The check is one
/// loopback request that either connects or is refused immediately, so
/// running it every few seconds costs close to nothing.
///
/// Deliberately owned by the **app root** rather than by
/// [StreamSessionNotifier] or a screen:
///
/// * A screen would be wrong — the cable can be plugged in at any moment,
///   including while the user is already on the capture screen about to hit
///   record, and that is exactly when "nothing happened" is least
///   explicable.
/// * The session notifier would be wrong for a subtler reason: a periodic
///   timer inside a provider that every screen builds leaves every widget
///   test that pumps one unable to settle (`!timersPending`). Putting it
///   here means tests that pump a single screen never start it, without any
///   test-only flag in production code.
class UsbAutoConnect {
  UsbAutoConnect(this._ref) {
    _timer = Timer.periodic(_interval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  static const _interval = Duration(seconds: 3);

  final Ref _ref;
  Timer? _timer;

  Future<void> _tick() =>
      _ref.read(streamSessionProvider.notifier).maybeAutoConnectOverUsb();

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

final usbAutoConnectProvider = Provider<UsbAutoConnect>((ref) {
  final autoConnect = UsbAutoConnect(ref);
  ref.onDispose(autoConnect.dispose);
  return autoConnect;
});
