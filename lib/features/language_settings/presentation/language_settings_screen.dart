import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_locale.dart';
import 'language_settings_provider.dart';

class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(languageSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Language')),
      body: RadioGroup<AppLocale>(
        groupValue: settings.locale,
        onChanged: (value) {
          if (value != null) {
            ref.read(languageSettingsProvider.notifier).setLocale(value);
          }
        },
        child: ListView(
          children: [
            for (final locale in AppLocale.values)
              RadioListTile<AppLocale>(
                value: locale,
                title: Text(locale.displayName, style: const TextStyle(color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}
