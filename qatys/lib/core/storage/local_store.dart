import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small key-value store for data that is not secret: the cached feed, the
/// offline queue, "permission already asked". The JWT never goes here; it
/// lives in `SecureSessionStorage` (brief, section 9).
abstract interface class LocalStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);

  /// Everything the app stored here. Called on logout, so the next person on
  /// a shared phone starts clean.
  Future<void> clearAll();
}

class SharedPreferencesStore implements LocalStore {
  SharedPreferencesStore([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);

  @override
  Future<void> clearAll() => _prefs.clear();
}

class InMemoryStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clearAll() async => values.clear();
}

/// Overridden in tests with an in-memory store.
final localStoreProvider = Provider<LocalStore>(
  (ref) => SharedPreferencesStore(),
);
