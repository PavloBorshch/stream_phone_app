import 'package:flutter/material.dart';

import '../../domain/settings_section.dart';

class SettingsSectionTile extends StatelessWidget {
  const SettingsSectionTile({super.key, required this.section, required this.onTap});

  final SettingsSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(section.icon, color: Colors.white70),
      title: Text(section.title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(section.subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }
}
