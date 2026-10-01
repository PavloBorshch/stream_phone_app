/// Where the composited capture feed should be sent: the paired PC
/// ("Leg A", WebRTC — see HELP.md §8), the configured RTMP/RTMPS/SRT
/// destinations ("Leg B" — `StreamDestination`), or both at once, fed from
/// the same capture session. Orthogonal to [CaptureMode] (camera vs
/// screencast) — the two choices are independent: this picks *where* the
/// feed goes, not *what* is captured.
enum BroadcastTarget {
  toPc('To PC'),
  toServices('To services'),
  both('Both');

  const BroadcastTarget(this.displayName);

  final String displayName;

  /// Whether this target asks for the paired-PC WebRTC leg (PLAN.md §1.5
  /// "Leg A").
  bool get includesPc => this == BroadcastTarget.toPc || this == BroadcastTarget.both;

  /// Whether this target asks for the configured RTMP/RTMPS/SRT destinations
  /// ("Leg B").
  bool get includesServices => this == BroadcastTarget.toServices || this == BroadcastTarget.both;

  /// Falls back to [toServices] for an unknown/corrupted stored value. Also
  /// what a fresh install starts with — the pre-existing behavior before
  /// this selector existed: publish to the configured destinations, with a
  /// paired PC never a guaranteed recipient even when connected.
  static BroadcastTarget fromName(String? name) {
    return BroadcastTarget.values.firstWhere(
      (value) => value.name == name,
      orElse: () => BroadcastTarget.toServices,
    );
  }
}
