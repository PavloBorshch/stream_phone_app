import 'package:flutter/material.dart';

/// Identifies each top-level settings section. [language] is the only one
/// with real functionality today (Phase 2); the rest are built out in
/// later plan phases and currently route to a placeholder.
enum SettingsSectionId {
  account,
  language,
  destinations,
  pcConnection,
  video,
  audio,
  network,
  onScreen,
  batteryPerformance,
  notifications,
}

class SettingsSection {
  const SettingsSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.pathSegment,
  });

  final SettingsSectionId id;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Segment appended to `/settings/` to reach this section's screen.
  final String pathSegment;
}

const settingsSections = [
  SettingsSection(
    id: SettingsSectionId.account,
    title: 'Account',
    subtitle: 'Sign in with email',
    icon: Icons.person,
    pathSegment: 'account',
  ),
  SettingsSection(
    id: SettingsSectionId.language,
    title: 'Language',
    subtitle: 'App display language',
    icon: Icons.language,
    pathSegment: 'language',
  ),
  SettingsSection(
    id: SettingsSectionId.destinations,
    title: 'Destinations & Accounts',
    subtitle: 'Connected platforms, custom RTMP/RTMPS/SRT, multistreaming',
    icon: Icons.podcasts,
    pathSegment: 'destinations',
  ),
  SettingsSection(
    id: SettingsSectionId.pcConnection,
    title: 'PC Connection',
    subtitle: 'Pairing, transport, auto-reconnect',
    icon: Icons.desktop_windows,
    pathSegment: 'pc-connection',
  ),
  SettingsSection(
    id: SettingsSectionId.video,
    title: 'Video',
    subtitle: 'Resolution, frame rate, bitrate, codec',
    icon: Icons.videocam,
    pathSegment: 'video',
  ),
  SettingsSection(
    id: SettingsSectionId.audio,
    title: 'Audio',
    subtitle: 'Microphone source, sample rate, monitoring',
    icon: Icons.mic,
    pathSegment: 'audio',
  ),
  SettingsSection(
    id: SettingsSectionId.network,
    title: 'Network',
    subtitle: 'Preferred network, buffer size, retries',
    icon: Icons.wifi,
    pathSegment: 'network',
  ),
  SettingsSection(
    id: SettingsSectionId.onScreen,
    title: 'On-Screen Elements',
    subtitle: 'Quick mute, stream health overlay',
    icon: Icons.layers,
    pathSegment: 'on-screen',
  ),
  SettingsSection(
    id: SettingsSectionId.batteryPerformance,
    title: 'Battery & Performance',
    subtitle: 'Battery saver, thermal throttling, screen awake',
    icon: Icons.battery_charging_full,
    pathSegment: 'battery-performance',
  ),
  SettingsSection(
    id: SettingsSectionId.notifications,
    title: 'Notifications & Alerts',
    subtitle: 'Connection lost alerts',
    icon: Icons.notifications,
    pathSegment: 'notifications',
  ),
];
