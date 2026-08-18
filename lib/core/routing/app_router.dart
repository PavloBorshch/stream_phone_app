import 'package:go_router/go_router.dart';

import '../../features/capture/presentation/capture_screen.dart';
import '../../features/language_settings/presentation/language_settings_screen.dart';
import '../../features/settings/domain/settings_section.dart';
import '../../features/settings/presentation/coming_soon_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const CaptureScreen()),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
      routes: [
        GoRoute(
          path: 'language',
          builder: (context, state) => const LanguageSettingsScreen(),
        ),
        for (final section in settingsSections)
          if (section.id != SettingsSectionId.language)
            GoRoute(
              path: section.pathSegment,
              builder: (context, state) => ComingSoonScreen(title: section.title),
            ),
      ],
    ),
  ],
);
