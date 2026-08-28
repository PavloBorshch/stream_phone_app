/// What to do when the battery runs low or the device gets hot.
enum PerformanceGuard {
  off('Off', 'Never change quality automatically'),
  lowerQuality('Lower quality', 'Drop to a lighter preset to keep streaming'),
  stopStream('Stop streaming', 'End the stream rather than run the battery flat');

  const PerformanceGuard(this.displayName, this.description);

  final String displayName;
  final String description;

  static PerformanceGuard fromName(String? name) {
    return PerformanceGuard.values.firstWhere(
      (value) => value.name == name,
      orElse: () => PerformanceGuard.lowerQuality,
    );
  }
}

class BatteryPerformanceSettings {
  const BatteryPerformanceSettings({
    required this.batteryGuard,
    required this.batteryThresholdPercent,
    required this.thermalGuard,
    required this.keepScreenAwake,
  });

  final PerformanceGuard batteryGuard;

  /// Battery percentage at which [batteryGuard] takes effect. Ignored while
  /// charging — a phone on a charger is not running out of anything.
  final int batteryThresholdPercent;

  final PerformanceGuard thermalGuard;

  /// Hold the screen on while capturing. Streaming with the screen off is
  /// fine on Android (the foreground service keeps capture alive), but the
  /// preview is also how the user frames the shot, so most will want this on.
  final bool keepScreenAwake;

  static const thresholdOptions = [5, 10, 15, 20, 30];

  static const defaults = BatteryPerformanceSettings(
    // Lowering quality is the conservative default: stopping someone's live
    // stream automatically is a much bigger surprise than a softer picture.
    batteryGuard: PerformanceGuard.lowerQuality,
    batteryThresholdPercent: 15,
    thermalGuard: PerformanceGuard.lowerQuality,
    keepScreenAwake: true,
  );

  factory BatteryPerformanceSettings.fromJson(Map<String, dynamic> json) {
    return BatteryPerformanceSettings(
      batteryGuard: PerformanceGuard.fromName(json['batteryGuard'] as String?),
      batteryThresholdPercent:
          json['batteryThresholdPercent'] as int? ?? defaults.batteryThresholdPercent,
      thermalGuard: PerformanceGuard.fromName(json['thermalGuard'] as String?),
      keepScreenAwake: json['keepScreenAwake'] as bool? ?? defaults.keepScreenAwake,
    );
  }

  Map<String, dynamic> toJson() => {
    'batteryGuard': batteryGuard.name,
    'batteryThresholdPercent': batteryThresholdPercent,
    'thermalGuard': thermalGuard.name,
    'keepScreenAwake': keepScreenAwake,
  };

  BatteryPerformanceSettings copyWith({
    PerformanceGuard? batteryGuard,
    int? batteryThresholdPercent,
    PerformanceGuard? thermalGuard,
    bool? keepScreenAwake,
  }) {
    return BatteryPerformanceSettings(
      batteryGuard: batteryGuard ?? this.batteryGuard,
      batteryThresholdPercent: batteryThresholdPercent ?? this.batteryThresholdPercent,
      thermalGuard: thermalGuard ?? this.thermalGuard,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BatteryPerformanceSettings &&
        other.batteryGuard == batteryGuard &&
        other.batteryThresholdPercent == batteryThresholdPercent &&
        other.thermalGuard == thermalGuard &&
        other.keepScreenAwake == keepScreenAwake;
  }

  @override
  int get hashCode =>
      Object.hash(batteryGuard, batteryThresholdPercent, thermalGuard, keepScreenAwake);
}
