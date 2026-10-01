import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'core/app_theme.dart';
import 'core/persistence/settings_repository.dart';
import 'core/persistence/settings_repository_provider.dart';
import 'core/routing/app_router.dart';
import 'features/pc_connection/presentation/usb_auto_connect.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settingsRepository = await SettingsRepository.create();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    ProviderScope(
      overrides: [settingsRepositoryProvider.overrideWithValue(settingsRepository)],
      child: const StreamingApp(),
    ),
  );
}

class StreamingApp extends ConsumerWidget {
  const StreamingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Started here, for the whole life of the app: a USB cable can be
    // plugged in at any point and the phone should connect to the PC on the
    // other end without being asked. See UsbAutoConnect for why it lives at
    // the root rather than in a screen or in StreamSessionNotifier.
    ref.watch(usbAutoConnectProvider);

    return MaterialApp.router(
      title: 'PhoneCam Stream',
      debugShowCheckedModeBanner: false,

      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,

      routerConfig: appRouter,
    );
  }
}
