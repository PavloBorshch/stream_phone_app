import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/usb_bridge_discovery.dart';
import '../domain/discovered_pc.dart';

final usbBridgeDiscoveryProvider = Provider<UsbBridgeDiscovery>(
  (ref) => const UsbBridgeDiscovery(),
);

/// What the phone currently knows about the USB cable.
class UsbDiscoveryState {
  const UsbDiscoveryState({this.searching = false, this.pc});

  final bool searching;

  /// The PC on the other end of the cable, or null when no tunnel is up.
  /// There is exactly one: the tunnel lands on a fixed local port, and only
  /// the machine holding the cable can be behind it.
  final DiscoveredPc? pc;

  bool get linkUp => pc != null;
}

/// Keeps [UsbDiscoveryState] current while something is watching.
///
/// Polled rather than event-driven because there is nothing to subscribe
/// to: Dart exposes no interface-change notification, and the answer to
/// "is a cable plugged in" only changes when a human plugs one in. The
/// cheap check ([UsbTetherDiscovery.isTetherLinkUp], a local interface
/// enumeration) runs on every tick; the actual subnet sweep only runs when
/// a link is up and nothing has been found yet, so the steady state costs
/// nothing once connected — and nothing at all with no cable attached.
///
/// `autoDispose`, like [lanDiscoveryProvider]: scanning is a pairing-screen
/// activity, not something the app should keep doing in the background.
class UsbDiscoveryNotifier extends AutoDisposeNotifier<UsbDiscoveryState> {
  static const _pollInterval = Duration(seconds: 3);

  Timer? _timer;
  bool _busy = false;
  // A probe can outlive the provider, and writing `state` after disposal
  // throws. This Riverpod version exposes no `ref.mounted`, so track it.
  bool _disposed = false;

  @override
  UsbDiscoveryState build() {
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });
    unawaited(_tick());
    return const UsbDiscoveryState();
  }

  /// Probes now rather than waiting for the next tick -- for a "search
  /// again" affordance, and right after the user has started the PC app.
  Future<void> refresh() => _tick();

  /// Polled because there is nothing to subscribe to: a cable being plugged
  /// in, adb setting up the tunnel, and the PC app starting are all
  /// invisible to this process. The probe is a loopback request that either
  /// connects or is refused immediately, so polling it costs almost nothing.
  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!_disposed) state = UsbDiscoveryState(searching: true, pc: state.pc);
      final pc = await ref.read(usbBridgeDiscoveryProvider).find();
      if (_disposed) return;
      state = UsbDiscoveryState(searching: false, pc: pc);
    } finally {
      _busy = false;
    }
  }
}

final usbDiscoveryProvider =
    NotifierProvider.autoDispose<UsbDiscoveryNotifier, UsbDiscoveryState>(
      UsbDiscoveryNotifier.new,
    );
