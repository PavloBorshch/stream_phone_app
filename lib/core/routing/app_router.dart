import 'package:go_router/go_router.dart';

import '../../features/audio_settings/presentation/audio_settings_screen.dart';
import '../../features/battery_performance/presentation/battery_performance_screen.dart';
import '../../features/auth/presentation/email_link_callback_screen.dart';
import '../../features/auth/presentation/email_login_screen.dart';
import '../../features/capture/presentation/capture_screen.dart';
import '../../features/destinations/presentation/destinations_screen.dart';
import '../../features/language_settings/presentation/language_settings_screen.dart';
import '../../features/network_settings/presentation/network_settings_screen.dart';
import '../../features/pc_connection/presentation/pairing_screen.dart';
import '../../features/pc_connection/presentation/pin_entry_page.dart';
import '../../features/pc_connection/presentation/qr_scan_page.dart';
import '../../features/settings/domain/settings_section.dart';
import '../../features/settings/presentation/coming_soon_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/video_settings/presentation/video_settings_screen.dart';

const _builtSections = {
  SettingsSectionId.account,
  SettingsSectionId.language,
  SettingsSectionId.destinations,
  SettingsSectionId.pcConnection,
  SettingsSectionId.video,
  SettingsSectionId.audio,
  SettingsSectionId.network,
  SettingsSectionId.batteryPerformance,
};

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const CaptureScreen()),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
      routes: [
        GoRoute(path: 'account', builder: (context, state) => const EmailLoginScreen()),
        GoRoute(path: 'language', builder: (context, state) => const LanguageSettingsScreen()),
        GoRoute(path: 'destinations', builder: (context, state) => const DestinationsScreen()),
        GoRoute(path: 'video', builder: (context, state) => const VideoSettingsScreen()),
        GoRoute(path: 'audio', builder: (context, state) => const AudioSettingsScreen()),
        GoRoute(path: 'network', builder: (context, state) => const NetworkSettingsScreen()),
        GoRoute(
          path: 'battery-performance',
          builder: (context, state) => const BatteryPerformanceScreen(),
        ),
        GoRoute(
          path: 'pc-connection',
          builder: (context, state) => const PairingScreen(),
          routes: [
            GoRoute(path: 'scan', builder: (context, state) => const QrScanPage()),
            GoRoute(path: 'manual', builder: (context, state) => const PinEntryPage()),
          ],
        ),
        for (final section in settingsSections)
          if (!_builtSections.contains(section.id))
            GoRoute(
              path: section.pathSegment,
              builder: (context, state) => ComingSoonScreen(title: section.title),
            ),
      ],
    ),
    // Landing route for the Firebase email sign-in link — see
    // AuthRepository's doc comment for what has to be true (App Link /
    // Universal Link verification) for the OS to actually route here.
    GoRoute(
      path: '/__/auth/action',
      builder: (context, state) => EmailLinkCallbackScreen(link: state.uri.toString()),
    ),
  ],
);
