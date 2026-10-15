import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> tokens);
  Future<void> clear();
}

/// Keychain / Android Keystore; isolated by API environment, never plaintext prefs.
class SecureTokenStore implements TokenStore {
  SecureTokenStore(String backend)
    : _key = 'fan-os-auth-v1-${sha256.convert(utf8.encode(backend))}';
  final String _key;
  final _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  @override
  Future<Map<String, dynamic>?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(Map<String, dynamic> tokens) =>
      _storage.write(key: _key, value: jsonEncode(tokens));
  @override
  Future<void> clear() => _storage.delete(key: _key);
}
