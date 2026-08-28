import 'dart:async';

import 'package:battery_plus/battery_plus.dart';

/// Battery level plus whether the phone is on external power.
class BatteryStatus {
  const BatteryStatus({required this.levelPercent, required this.isOnPower});

  final int levelPercent;

  /// True for charging *and* "plugged in but not charging" (a phone at a
  /// charge limit): either way it is not running out, which is the only
  /// question the battery guard asks.
  final bool isOnPower;

  static const unknown = BatteryStatus(levelPercent: 100, isOnPower: true);

  @override
  bool operator ==(Object other) =>
      other is BatteryStatus &&
      other.levelPercent == levelPercent &&
      other.isOnPower == isOnPower;

  @override
  int get hashCode => Object.hash(levelPercent, isOnPower);
}

/// Wraps `battery_plus` into a single polled status stream.
///
/// `battery_plus` streams charging *state* changes but not level, so level has
/// to be polled. The interval is deliberately slow — a percentage point takes
/// minutes to move, and this runs for the whole length of a stream.
class BatteryService {
  BatteryService([Battery? battery, this.pollInterval = const Duration(minutes: 1)])
      : _battery = battery ?? Battery();

  final Battery _battery;
  final Duration pollInterval;

  Future<BatteryStatus> current() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      return BatteryStatus(levelPercent: level, isOnPower: _isOnPower(state));
    } on Exception {
      // A phone that won't report its battery must not be treated as flat.
      return BatteryStatus.unknown;
    }
  }

  Stream<BatteryStatus> changes() {
    // Merges the two triggers: a charger being plugged in should register
    // immediately, while the level itself only needs the slow poll.
    final ticks = Stream<void>.periodic(pollInterval);
    final stateChanges = _battery.onBatteryStateChanged.map<void>((_) {});

    late StreamController<BatteryStatus> controller;
    StreamSubscription<void>? tickSubscription;
    StreamSubscription<void>? stateSubscription;

    Future<void> emit() async {
      if (controller.isClosed) return;
      controller.add(await current());
    }

    controller = StreamController<BatteryStatus>(
      onListen: () {
        unawaited(emit());
        tickSubscription = ticks.listen((_) => emit());
        stateSubscription = stateChanges.listen((_) => emit());
      },
      onCancel: () async {
        await tickSubscription?.cancel();
        await stateSubscription?.cancel();
      },
    );

    return controller.stream;
  }

  static bool _isOnPower(BatteryState state) => switch (state) {
    BatteryState.charging || BatteryState.full || BatteryState.connectedNotCharging => true,
    BatteryState.discharging => false,
    // Unknown is treated as on-power for the same reason as above: guessing
    // "on battery" would throttle a device that may be plugged in.
    BatteryState.unknown => true,
  };
}
