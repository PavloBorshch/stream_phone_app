import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/settings_section.dart';
import 'widgets/settings_section_tile.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView.separated(
        itemCount: settingsSections.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
        itemBuilder: (context, index) {
          final section = settingsSections[index];
          return SettingsSectionTile(
            section: section,
            onTap: () => context.push('/settings/${section.pathSegment}'),
          );
        },
      ),
    );
  }
}
