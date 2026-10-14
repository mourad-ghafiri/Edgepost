import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain (iOS) / Keystore-backed (Android) storage for API tokens and mail
/// service keys. Nothing secret is ever written anywhere else.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _s;

  /// Tokens (without their secrets), the added accounts and which one is
  /// active: one document, written only by the app, so the background check
  /// (which only reads it) can never undo a switch.
  static const _vaultKey = 'vault';
  static String _tokenKey(String id) => 'token.$id';
  static String _mailKey(String accountId) => 'mail.$accountId';
  static const _settingsKey = 'settings';

  Future<Map<String, dynamic>?> readVault() async {
    final raw = await _s.read(key: _vaultKey);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> writeVault(Map<String, dynamic> vault) => _s.write(key: _vaultKey, value: jsonEncode(vault));

  Future<String?> readToken(String credentialId) => _s.read(key: _tokenKey(credentialId));

  Future<void> writeToken(String credentialId, String token) =>
      _s.write(key: _tokenKey(credentialId), value: token);

  Future<void> deleteToken(String credentialId) => _s.delete(key: _tokenKey(credentialId));

  /// Mail service endpoint + bearer key for one Cloudflare account.
  Future<Map<String, dynamic>?> readMailService(String accountId) async {
    final raw = await _s.read(key: _mailKey(accountId));
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> writeMailService(String accountId, Map<String, dynamic> value) =>
      _s.write(key: _mailKey(accountId), value: jsonEncode(value));

  Future<void> deleteMailService(String accountId) => _s.delete(key: _mailKey(accountId));

  Future<Map<String, dynamic>> readSettings() async {
    final raw = await _s.read(key: _settingsKey);
    return raw == null ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> writeSettings(Map<String, dynamic> settings) =>
      _s.write(key: _settingsKey, value: jsonEncode(settings));

  static Future<void> _settingsQueue = Future.value();

  /// Read-modify-write of the settings, one at a time in this isolate, so
  /// concurrent writers (sync cursors, alert state, preferences) never
  /// overwrite each other's keys.
  Future<T> updateSettings<T>(T Function(Map<String, dynamic> settings) change) {
    final done = _settingsQueue.then((_) async {
      final s = await readSettings();
      final result = change(s);
      await writeSettings(s);
      return result;
    });
    _settingsQueue = done.then((_) {}, onError: (_) {});
    return done;
  }
}
