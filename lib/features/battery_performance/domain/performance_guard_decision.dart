import '../data/battery_service.dart';
import 'battery_performance_settings.dart';
import 'device_health.dart';

/// What the battery and thermal guards want done about quality right now.
///
/// Pure so the policy can be unit tested without a device that is actually
/// hot or flat.
class PerformanceGuardDecision {
  const PerformanceGuardDecision({
    required this.ceilingScale,
    required this.frameRateCap,
    required this.shouldStop,
    this.reason,
  });

  /// Fraction of the configured bitrate the encoders may use.
  final double ceilingScale;

  /// Frame-rate cap, or 0 for "no cap".
  final int frameRateCap;

  final bool shouldStop;

  /// User-facing explanation, present only when something is being limited —
  /// a guard that silently halves quality would look like a bug.
  final String? reason;

  static const unconstrained = PerformanceGuardDecision(
    ceilingScale: 1.0,
    frameRateCap: 0,
    shouldStop: false,
  );

  bool get isConstrained => ceilingScale < 1.0 || frameRateCap > 0;

  /// How far quality is cut when a guard trips. One decisive step rather than
  /// a gradual ramp: the network controller already handles gradual, and a
  /// hot or nearly-flat phone needs relief now, not in a minute.
  static const throttledScale = 0.5;
  static const throttledFrameRate = 30;

  static PerformanceGuardDecision evaluate({
    required BatteryPerformanceSettings settings,
    required BatteryStatus battery,
    required ThermalStatus thermal,
  }) {
    // Thermal is checked first: an overheating phone will throttle itself
    // regardless of charge, and on a charger the battery guard never fires,
    // so thermal is the only guard that can act in that case.
    if (thermal.needsThrottling && settings.thermalGuard != PerformanceGuard.off) {
      if (settings.thermalGuard == PerformanceGuard.stopStream) {
        return PerformanceGuardDecision(
          ceilingScale: 1.0,
          frameRateCap: 0,
          shouldStop: true,
          reason: 'Stopped: the phone is too hot (${thermal.displayName.toLowerCase()}).',
        );
      }
      return PerformanceGuardDecision(
        ceilingScale: throttledScale,
        frameRateCap: throttledFrameRate,
        shouldStop: false,
        reason: 'Quality reduced: the phone is running hot.',
      );
    }

    // A phone on external power is not running out, so the battery guard is
    // skipped entirely rather than tripping at a low-but-rising level.
    final batteryLow =
        !battery.isOnPower && battery.levelPercent <= settings.batteryThresholdPercent;
    if (batteryLow && settings.batteryGuard != PerformanceGuard.off) {
      if (settings.batteryGuard == PerformanceGuard.stopStream) {
        return PerformanceGuardDecision(
          ceilingScale: 1.0,
          frameRateCap: 0,
          shouldStop: true,
          reason: 'Stopped: battery is at ${battery.levelPercent}%.',
        );
      }
      return PerformanceGuardDecision(
        ceilingScale: throttledScale,
        frameRateCap: throttledFrameRate,
        shouldStop: false,
        reason: 'Quality reduced: battery is at ${battery.levelPercent}%.',
      );
    }

    return unconstrained;
  }

  @override
  bool operator ==(Object other) =>
      other is PerformanceGuardDecision &&
      other.ceilingScale == ceilingScale &&
      other.frameRateCap == frameRateCap &&
      other.shouldStop == shouldStop;

  @override
  int get hashCode => Object.hash(ceilingScale, frameRateCap, shouldStop);
}
