import 'package:flutter/material.dart';

/// A settings row that picks one value out of a fixed set, shared by the
/// Video and Audio settings screens.
///
/// Options the device can't honour are passed in [unavailable] rather than
/// omitted: hiding them would make a phone without (say) an AV1 encoder look
/// like a phone where AV1 doesn't exist as a concept, and the user would have
/// no way to tell why the option they read about isn't there.
class SettingsOptionTile<T> extends StatelessWidget {
  const SettingsOptionTile({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.onChanged,
    this.subtitle,
    this.unavailable = const {},
    this.unavailableNote = 'Not supported on this device',
  });

  final String title;
  final String? subtitle;
  final T value;
  final List<T> options;
  final String Function(T option) labelBuilder;
  final ValueChanged<T> onChanged;
  final Set<T> unavailable;
  final String unavailableNote;

  @override
  Widget build(BuildContext context) {
    // DropdownButton sizes its closed state (and, from that, its open menu —
    // see menuWidth below) to the *widest of every item*, not just the
    // selected one — including unavailable options' long "<label> — <note>"
    // text. Left alone, that made the closed button (and therefore this
    // ListTile's trailing slot) demand far more width than the tile had,
    // which squeezed the title/subtitle text down to almost nothing and
    // wrapped it one letter per line. selectedItemBuilder decouples what's
    // shown closed (always just the short label) from the open menu's items.
    final menuWidth = (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 320.0);

    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: DropdownButton<T>(
        value: value,
        dropdownColor: const Color(0xFF212121),
        underline: const SizedBox.shrink(),
        menuWidth: menuWidth,
        selectedItemBuilder: (context) => [
          for (final option in options)
            Text(
              labelBuilder(option),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(color: Colors.white),
            ),
        ],
        onChanged: (selected) {
          if (selected != null && !unavailable.contains(selected)) {
            onChanged(selected);
          }
        },
        items: [
          for (final option in options)
            DropdownMenuItem<T>(
              value: option,
              enabled: !unavailable.contains(option),
              child: Text(
                unavailable.contains(option)
                    ? '${labelBuilder(option)} — $unavailableNote'
                    : labelBuilder(option),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: unavailable.contains(option) ? Colors.white38 : Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Section header used to group rows on the settings detail screens.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
