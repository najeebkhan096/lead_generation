import 'dart:js_interop';

@JS('localStorage')
external _WebStorage? get _localStorage;

extension type _WebStorage._(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
}

/// Browser `localStorage`, guarded: private windows and blocked site data make
/// the accessor throw, which must never break the app.
class PrefsStorage {
  PrefsStorage._();

  static String? read(String key) {
    try {
      return _localStorage?.getItem(key.toJS)?.toDart;
    } catch (_) {
      return null;
    }
  }

  static void write(String key, String value) {
    try {
      _localStorage?.setItem(key.toJS, value.toJS);
    } catch (_) {
      // Not remembered; the preference still applies for this session.
    }
  }
}
