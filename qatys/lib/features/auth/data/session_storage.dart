import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/session.dart';
import 'auth_json.dart';

abstract interface class SessionStorage {
  Future<Session?> read();

  Future<void> write(Session session);

  /// Removes every stored value, so nothing is left on a shared device.
  Future<void> clear();
}

/// Keeps the JWT in the platform keystore/keychain, never in plain
/// SharedPreferences (brief, section 9: "Token on a shared device").
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'session.token';
  static const _studentKey = 'session.student';

  final FlutterSecureStorage _storage;

  @override
  Future<Session?> read() async {
    final token = await _storage.read(key: _tokenKey);
    final student = await _storage.read(key: _studentKey);
    if (token == null || student == null) return null;

    try {
      final json = jsonDecode(student);
      if (json is! Map<String, Object?>) throw const FormatException();
      return Session(token: token, student: studentFromJson(json));
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(Session session) async {
    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(
      key: _studentKey,
      value: jsonEncode(studentToJson(session.student)),
    );
  }

  @override
  Future<void> clear() => _storage.deleteAll();
}
