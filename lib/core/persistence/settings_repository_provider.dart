import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_repository.dart';

/// Overridden in `main()` with the real [SettingsRepository] once
/// `SettingsRepository.create()` resolves, before [ProviderScope] is built.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw UnimplementedError(
    'settingsRepositoryProvider must be overridden with a real SettingsRepository in main()',
  );
});
