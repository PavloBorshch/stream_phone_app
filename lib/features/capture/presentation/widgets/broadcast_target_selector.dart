import 'package:flutter/material.dart';

import '../../domain/broadcast_target.dart';

/// Segmented selector for [BroadcastTarget] ("To PC" / "To services" /
/// "Both"), placed alongside [CaptureModeToggle] and using the same visual
/// language (a pill with a sliding highlight), extended to three segments.
/// Orthogonal to the mode toggle: this picks *where* the feed goes, not
/// *what* is captured.
class BroadcastTargetSelector extends StatelessWidget {
  const BroadcastTargetSelector({
    super.key,
    required this.target,
    required this.onChanged,
    this.enabled = true,
  });

  final BroadcastTarget target;
  final ValueChanged<BroadcastTarget> onChanged;

  /// Disabled (but still visible, so the current selection stays legible)
  /// while a stream is live — the native publisher session is configured
  /// once at `start()` and has no way to retarget the PC/services split
  /// mid-stream.
  final bool enabled;

  static const double _width = 240;
  static const double _height = 32;
  static const _alignments = [Alignment.centerLeft, Alignment.center, Alignment.centerRight];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = BroadcastTarget.values.indexOf(target);

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        width: _width,
        height: _height,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(_height / 2),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              alignment: _alignments[selectedIndex],
              child: FractionallySizedBox(
                widthFactor: 1 / BroadcastTarget.values.length,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(_height / 2),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final value in BroadcastTarget.values)
                  _TargetLabel(
                    label: value.displayName,
                    isSelected: value == target,
                    onTap: enabled ? () => onChanged(value) : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetLabel extends StatelessWidget {
  const _TargetLabel({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
