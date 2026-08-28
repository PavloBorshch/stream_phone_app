import 'package:flutter/material.dart';

import '../../domain/video_overrides.dart';
import '../../domain/video_settings.dart';
import 'bitrate_field.dart';

/// Editor for one destination's [VideoOverrides]. Pops with the new
/// overrides, or `null` if the user dismissed it without saving.
///
/// Each row has an explicit "Use global" entry rather than a separate
/// enable switch, because the meaningful state is three-way per field —
/// inherited, or overridden to a specific value — and a switch would need a
/// second control to say which value it switched to.
class DestinationOverridesSheet extends StatefulWidget {
  const DestinationOverridesSheet({
    super.key,
    required this.destinationName,
    required this.base,
    required this.overrides,
  });

  final String destinationName;
  final VideoSettings base;
  final VideoOverrides overrides;

  @override
  State<DestinationOverridesSheet> createState() => _DestinationOverridesSheetState();
}

class _DestinationOverridesSheetState extends State<DestinationOverridesSheet> {
  late VideoResolution? _resolution = widget.overrides.resolution;
  late VideoFrameRate? _frameRate = widget.overrides.frameRate;
  late int? _bitrateKbps = widget.overrides.bitrateKbps;

  VideoOverrides get _current => VideoOverrides(
    resolution: _resolution,
    frameRate: _frameRate,
    bitrateKbps: _bitrateKbps,
  );

  @override
  Widget build(BuildContext context) {
    final effective = _current.applyTo(widget.base);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.destinationName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Override the global video settings for this destination only.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _OverrideRow<VideoResolution>(
              label: 'Resolution',
              value: _resolution,
              options: VideoResolution.values,
              labelBuilder: (option) => option.displayName,
              inheritedLabel: widget.base.resolution.displayName,
              onChanged: (value) => setState(() => _resolution = value),
            ),
            _OverrideRow<VideoFrameRate>(
              label: 'Frame rate',
              value: _frameRate,
              options: VideoFrameRate.values,
              labelBuilder: (option) => option.displayName,
              inheritedLabel: widget.base.frameRate.displayName,
              onChanged: (value) => setState(() => _frameRate = value),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _bitrateKbps == null ? 'Bitrate (global)' : 'Bitrate',
                  style: const TextStyle(color: Colors.white),
                ),
                // Typing a value here — like dragging the slider below —
                // switches this field from inheriting the global bitrate to
                // an explicit override, same as every other override row.
                BitrateField(
                  value: _bitrateKbps ?? widget.base.bitrateKbps,
                  onChanged: (value) => setState(() => _bitrateKbps = value),
                ),
              ],
            ),
            Slider(
              value: (_bitrateKbps ?? widget.base.bitrateKbps)
                  .clamp(VideoSettings.minBitrateKbps, VideoSettings.maxBitrateKbps)
                  .toDouble(),
              min: VideoSettings.minBitrateKbps.toDouble(),
              max: VideoSettings.maxBitrateKbps.toDouble(),
              divisions: (VideoSettings.maxBitrateKbps - VideoSettings.minBitrateKbps) ~/ 250,
              onChanged: (value) => setState(() => _bitrateKbps = value.round()),
            ),
            if (_bitrateKbps != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _bitrateKbps = null),
                  child: const Text('Use global bitrate'),
                ),
              ),
            const Divider(color: Colors.white24),
            Text(
              'Effective: ${effective.resolution.displayName} / '
              '${effective.frameRate.displayName} / ${effective.bitrateKbps} kbps',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(VideoOverrides.none),
                  child: const Text('Clear all'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_current),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A dropdown whose null value means "inherit the global setting".
class _OverrideRow<T> extends StatelessWidget {
  const _OverrideRow({
    required this.label,
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.inheritedLabel,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<T> options;
  final String Function(T option) labelBuilder;
  final String inheritedLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    // See SettingsOptionTile's build() for why selectedItemBuilder and
    // menuWidth are both needed: without them, the long "Global (<label>)"
    // item alone inflates the closed button (DropdownButton sizes to its
    // widest item, not the selected one) enough to squeeze this Row's label
    // text down to almost nothing, wrapping it one letter per line.
    final menuWidth = (MediaQuery.sizeOf(context).width - 64).clamp(0.0, 280.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white)),
        DropdownButton<T?>(
          value: value,
          dropdownColor: const Color(0xFF212121),
          underline: const SizedBox.shrink(),
          menuWidth: menuWidth,
          selectedItemBuilder: (context) => [
            Text(
              'Global',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(color: Colors.white54),
            ),
            for (final option in options)
              Text(
                labelBuilder(option),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(color: Colors.white),
              ),
          ],
          onChanged: onChanged,
          items: [
            DropdownMenuItem<T?>(
              value: null,
              child: Text(
                'Global ($inheritedLabel)',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            for (final option in options)
              DropdownMenuItem<T?>(
                value: option,
                child: Text(
                  labelBuilder(option),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
