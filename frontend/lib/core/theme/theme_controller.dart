import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_theme.dart';
import 'prefs_storage.dart';

/// Owns light / dark / system and keeps [AppTheme.palette] in step.
///
/// Colors are read through `AppTheme.<token>` rather than `Theme.of(context)`,
/// so a switch has to re-run every widget's `build`: [apply] swaps the palette
/// and then marks the whole element tree dirty (state — scroll positions,
/// forms, running scans' pages — is kept; only `build` re-runs).
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController({ThemeMode? initial}) {
    _mode = initial ?? _read();
    AppTheme.palette = _paletteFor(_mode);
    WidgetsBinding.instance.addObserver(this);
  }

  static const _key = 'leadfinder.themeMode';

  static ThemeController? _shared;

  /// The controller provided above [context]; a standalone one when the tree
  /// has none (widget tests that build their own app).
  static ThemeController of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ThemeScope>()?.notifier ?? (_shared ??= ThemeController());

  late ThemeMode _mode;

  ThemeMode get mode => _mode;
  bool get isDark => AppTheme.isDark;

  static ThemeMode _read() => switch (PrefsStorage.read(_key)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static AppPalette _paletteFor(ThemeMode mode) {
    final dark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system && PlatformDispatcher.instance.platformBrightness == Brightness.dark);
    return dark ? AppPalette.dark : AppPalette.light;
  }

  /// Picks a mode and remembers it.
  void setMode(ThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    PrefsStorage.write(_key, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
    _apply();
  }

  /// Light ⇄ dark (from whatever is showing now).
  void toggle() => setMode(isDark ? ThemeMode.light : ThemeMode.dark);

  @override
  void didChangePlatformBrightness() {
    if (_mode == ThemeMode.system) _apply();
  }

  void _apply() {
    final next = _paletteFor(_mode);
    final changed = next != AppTheme.palette;
    AppTheme.palette = next;
    if (changed) _rebuildEverything();
    notifyListeners();
  }

  static void _rebuildEverything() {
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Makes a [ThemeController] reachable with [ThemeController.of].
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({super.key, required ThemeController controller, required super.child}) : super(notifier: controller);
}
