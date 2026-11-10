/// In-memory fallback used by tests and non-web builds.
class PrefsStorage {
  PrefsStorage._();

  static final Map<String, String> _values = {};

  static String? read(String key) => _values[key];

  static void write(String key, String value) => _values[key] = value;
}
