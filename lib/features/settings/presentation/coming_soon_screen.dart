import 'package:flutter/material.dart';

/// Placeholder for settings sections whose functionality belongs to a
/// later plan phase (Destinations, PC Connection, Video, Audio, Network,
/// On-Screen Elements, Battery & Performance, Notifications) — the section
/// is navigable now so the settings shell is complete, but not yet built.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This section is not built yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
