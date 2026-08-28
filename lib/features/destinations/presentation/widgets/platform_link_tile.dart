import 'package:flutter/material.dart';

/// One "connect account" row on [DestinationsScreen] for an OAuth-capable
/// platform (Twitch, Kick).
class PlatformLinkTile extends StatelessWidget {
  const PlatformLinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isLinking,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLinking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: isLinking
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: isLinking ? null : onTap,
    );
  }
}
