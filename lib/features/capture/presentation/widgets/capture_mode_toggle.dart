import 'package:flutter/material.dart';
import '../../domain/capture_mode.dart';

class CaptureModeToggle extends StatelessWidget {
  const CaptureModeToggle({super.key, required this.mode, required this.onChanged});

  final CaptureMode mode;
  final ValueChanged<CaptureMode> onChanged;

  static const double _width = 220;
  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = mode == CaptureMode.camera ? 0 : 1;

    return Container(
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
            alignment: selectedIndex == 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
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
              _ModeLabel(
                label: 'Camera',
                isSelected: selectedIndex == 0,
                onTap: () => onChanged(CaptureMode.camera),
              ),
              _ModeLabel(
                label: 'Screencast',
                isSelected: selectedIndex == 1,
                onTap: () => onChanged(CaptureMode.screencast),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeLabel extends StatelessWidget {
  const _ModeLabel({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

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
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
