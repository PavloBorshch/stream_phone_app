import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/video_settings.dart';

/// Compact numeric entry for a bitrate, shared by the main Video settings
/// screen and the per-destination overrides sheet — both previously offered
/// only a [Slider], which makes it slow (and on a coarse touch target,
/// imprecise) to land on an exact value a destination's ingest requires.
///
/// Kept in sync with [value] from outside (the slider dragging, or a
/// "Reset"/"Use global" action resetting it) without fighting the user's own
/// typing: the external value only overwrites the field's text while it
/// isn't focused, the same guard any external-state-into-a-TextField widget
/// needs.
class BitrateField extends StatefulWidget {
  const BitrateField({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<BitrateField> createState() => _BitrateFieldState();
}

class _BitrateFieldState extends State<BitrateField> {
  late final TextEditingController _controller = TextEditingController(text: '${widget.value}');
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant BitrateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focusNode.hasFocus) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null) {
      // Not a number (e.g. left empty) — revert rather than send garbage
      // to the notifier or leave the field showing something unconfirmed.
      _controller.text = '${widget.value}';
      return;
    }
    final clamped = parsed.clamp(VideoSettings.minBitrateKbps, VideoSettings.maxBitrateKbps);
    if (clamped != parsed) {
      _controller.text = '$clamped';
    }
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        textAlign: TextAlign.right,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(color: Colors.white70, fontSize: 14),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
          suffixText: ' kbps',
          suffixStyle: TextStyle(color: Colors.white70, fontSize: 14),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
        ),
        onSubmitted: _submit,
        onTapOutside: (_) => _submit(_controller.text),
      ),
    );
  }
}
