import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository_provider.dart';
import 'package:stream_phone_cam/features/audio_settings/presentation/audio_settings_screen.dart';
import 'package:stream_phone_cam/features/auth/presentation/email_login_screen.dart';
import 'package:stream_phone_cam/features/destinations/presentation/destinations_screen.dart';
import 'package:stream_phone_cam/features/language_settings/presentation/language_settings_screen.dart';
import 'package:stream_phone_cam/features/settings/domain/settings_section.dart';
import 'package:stream_phone_cam/features/settings/presentation/coming_soon_screen.dart';
import 'package:stream_phone_cam/features/settings/presentation/settings_screen.dart';
import 'package:stream_phone_cam/features/video_settings/presentation/video_settings_screen.dart';

const _builtSections = {
  SettingsSectionId.account,
  SettingsSectionId.language,
  SettingsSectionId.destinations,
  SettingsSectionId.video,
  SettingsSectionId.audio,
};

void main() {
  late SettingsRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = await SettingsRepository.create();
  });

  Future<void> setLargeSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
          routes: [
            GoRoute(path: 'account', builder: (c, s) => const EmailLoginScreen()),
            GoRoute(path: 'language', builder: (c, s) => const LanguageSettingsScreen()),
            GoRoute(path: 'destinations', builder: (c, s) => const DestinationsScreen()),
            GoRoute(path: 'video', builder: (c, s) => const VideoSettingsScreen()),
            GoRoute(path: 'audio', builder: (c, s) => const AudioSettingsScreen()),
            for (final section in settingsSections)
              if (!_builtSections.contains(section.id))
                GoRoute(
                  path: section.pathSegment,
                  builder: (c, s) => ComingSoonScreen(title: section.title),
                ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets('lists every settings section', (tester) async {
    await setLargeSurface(tester);
    await pumpSettings(tester);
    for (final section in settingsSections) {
      expect(find.text(section.title), findsOneWidget);
    }
  });

  testWidgets('tapping Language navigates to the language picker', (tester) async {
    await setLargeSurface(tester);
    await pumpSettings(tester);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    expect(find.byType(LanguageSettingsScreen), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('tapping a not-yet-built section shows the placeholder', (tester) async {
    await setLargeSurface(tester);
    await pumpSettings(tester);
    await tester.tap(find.text('Network'));
    await tester.pumpAndSettle();

    expect(find.byType(ComingSoonScreen), findsOneWidget);
    expect(find.text('This section is not built yet.'), findsOneWidget);
  });

  testWidgets('tapping Account navigates to the email login screen', (tester) async {
    await setLargeSurface(tester);
    await pumpSettings(tester);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    expect(find.byType(EmailLoginScreen), findsOneWidget);
  });

  testWidgets('tapping Video navigates to the video settings screen', (tester) async {
    await setLargeSurface(tester);
    await pumpSettings(tester);
    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();

    expect(find.byType(VideoSettingsScreen), findsOneWidget);
    expect(find.text('Resolution'), findsOneWidget);
  });

  testWidgets('tapping Audio navigates to the audio settings screen', (tester) async {
    await setLargeSurface(tester);
    await pumpSettings(tester);
    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();

    expect(find.byType(AudioSettingsScreen), findsOneWidget);
    expect(find.text('Microphone'), findsOneWidget);
  });

  testWidgets('tapping Destinations & Accounts navigates to the destinations screen', (tester) async {
    await setLargeSurface(tester);
    await pumpSettings(tester);
    await tester.tap(find.text('Destinations & Accounts'));
    await tester.pumpAndSettle();

    expect(find.byType(DestinationsScreen), findsOneWidget);
  });
}
