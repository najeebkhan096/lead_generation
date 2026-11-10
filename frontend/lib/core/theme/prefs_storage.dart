/// Tiny key-value storage for per-browser UI preferences (theme, sidebar).
/// The web build persists to `localStorage`; everywhere else (unit tests) it
/// is in memory. It never throws — a blocked or full storage just means the
/// preference isn't remembered.
library;

export 'prefs_storage_stub.dart' if (dart.library.js_interop) 'prefs_storage_web.dart';
