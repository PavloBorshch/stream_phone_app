import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository.dart';
import 'package:stream_phone_cam/core/persistence/settings_repository_provider.dart';
import 'package:stream_phone_cam/features/language_settings/presentation/language_settings_screen.dart';
import 'package:stream_phone_cam/features/settings/domain/settings_section.dart';
import 'package:stream_phone_cam/features/settings/presentation/coming_soon_screen.dart';
import 'package:stream_phone_cam/features/settings/presentation/settings_screen.dart';

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
            GoRoute(path: 'language', builder: (c, s) => const LanguageSettingsScreen()),
            for (final section in settingsSections)
              if (section.id != SettingsSectionId.language)
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
    await tester.tap(find.text('Destinations & Accounts'));
    await tester.pumpAndSettle();

    expect(find.byType(ComingSoonScreen), findsOneWidget);
    expect(find.text('This section is not built yet.'), findsOneWidget);
  });
}
