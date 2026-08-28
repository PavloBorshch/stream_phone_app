/// How hot the device is, as reported by Android's thermal API.
///
/// Mirrors `PowerManager.THERMAL_STATUS_*`, plus [unknown] for devices that
/// cannot report it (below API 29) — deliberately distinct from [none], since
/// "cool" and "we have no idea" must lead to different decisions.
enum ThermalStatus {
  unknown(-1),
  none(0),
  light(1),
  moderate(2),
  severe(3),
  critical(4),
  emergency(5),
  shutdown(6);

  const ThermalStatus(this.code);

  final int code;

  static ThermalStatus fromCode(int? code) {
    return ThermalStatus.values.firstWhere(
      (value) => value.code == code,
      orElse: () => ThermalStatus.unknown,
    );
  }

  /// At [severe] and above the SoC is already throttling itself, so the
  /// encoder will miss its target regardless of what we ask for; backing off
  /// first keeps the stream smooth instead of letting frames drop.
  /// [moderate] is deliberately *not* included — it is common under normal
  /// sustained recording and acting on it would degrade quality constantly.
  bool get needsThrottling => switch (this) {
    ThermalStatus.severe ||
    ThermalStatus.critical ||
    ThermalStatus.emergency ||
    ThermalStatus.shutdown => true,
    _ => false,
  };

  String get displayName => switch (this) {
    ThermalStatus.unknown => 'Unknown',
    ThermalStatus.none => 'Normal',
    ThermalStatus.light => 'Slightly warm',
    ThermalStatus.moderate => 'Warm',
    ThermalStatus.severe => 'Hot',
    ThermalStatus.critical => 'Very hot',
    ThermalStatus.emergency => 'Overheating',
    ThermalStatus.shutdown => 'Shutting down',
  };
}
