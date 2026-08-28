/// Running total of bytes this app has published over mobile data.
///
/// Tracked in its own period because a data cap is, in practice, a monthly
/// allowance: [periodStart] records which month the total belongs to, and
/// [rolledOver] rolls it forward rather than letting last month's usage keep
/// triggering warnings forever. The user can also reset it by hand when their
/// billing cycle doesn't start on the 1st.
class CellularUsage {
  const CellularUsage({required this.bytesSent, required this.periodStart});

  final int bytesSent;
  final DateTime periodStart;

  static CellularUsage empty(DateTime now) =>
      CellularUsage(bytesSent: 0, periodStart: DateTime(now.year, now.month));

  double get megabytesSent => bytesSent / (1024 * 1024);

  /// This total carried into the calendar month containing [now], reset to
  /// zero if that is a later month than [periodStart].
  CellularUsage rolledOver(DateTime now) {
    final currentPeriod = DateTime(now.year, now.month);
    if (currentPeriod.isAfter(periodStart)) return CellularUsage.empty(now);
    return this;
  }

  CellularUsage plus(int bytes) {
    if (bytes <= 0) return this;
    return CellularUsage(bytesSent: bytesSent + bytes, periodStart: periodStart);
  }

  /// Fraction of [capMb] used, or `null` when no cap is set. Can exceed 1.
  double? fractionOfCap(int? capMb) {
    if (capMb == null || capMb <= 0) return null;
    return megabytesSent / capMb;
  }

  factory CellularUsage.fromJson(Map<String, dynamic> json) {
    return CellularUsage(
      bytesSent: json['bytesSent'] as int? ?? 0,
      periodStart: DateTime.tryParse(json['periodStart'] as String? ?? '') ?? DateTime(1970),
    );
  }

  Map<String, dynamic> toJson() => {
    'bytesSent': bytesSent,
    'periodStart': periodStart.toIso8601String(),
  };

  @override
  bool operator ==(Object other) {
    return other is CellularUsage &&
        other.bytesSent == bytesSent &&
        other.periodStart == periodStart;
  }

  @override
  int get hashCode => Object.hash(bytesSent, periodStart);
}
