import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage for secrets that must never land in [SettingsRepository]'s
/// plain JSON blobs: OAuth tokens, PC pairing shared secrets, etc.
///
/// Backed by the OS keychain/keystore (iOS Keychain / Android Keystore).
class SecureTokenStore {
  const SecureTokenStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);
}
