import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Generic JSON-blob persistence for non-sensitive settings domains.
///
/// Each settings domain (video, audio, network, language, ...) stores one
/// JSON object under its own key. Never store secrets here — use
/// [SecureTokenStore] for those.
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsRepository> create() async {
    return SettingsRepository(await SharedPreferences.getInstance());
  }

  Map<String, dynamic>? readJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> writeJson(String key, Map<String, dynamic> value) {
    return _prefs.setString(key, jsonEncode(value));
  }

  Future<void> remove(String key) => _prefs.remove(key);
}
