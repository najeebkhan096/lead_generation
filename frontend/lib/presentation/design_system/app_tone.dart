import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The semantic meaning a color carries. Badges, alerts, stat cards, progress
/// bars and icon tiles all take a tone, so "success is green" is decided once.
///
///  * [primary] – brand / selected / in progress
///  * [success] – completed, verified, healthy
///  * [warning] – pending, partial, needs attention
///  * [error]   – failed, destructive
///  * [info]    – neutral information, active
///  * [neutral] – secondary, disabled, unknown
enum AppTone { neutral, primary, success, warning, error, info }

extension AppToneColors on AppTone {
  /// The faint fill behind text or an icon.
  Color get surface => switch (this) {
        AppTone.neutral => AppTheme.neutral100,
        AppTone.primary => AppTheme.primary100,
        AppTone.success => AppTheme.success100,
        AppTone.warning => AppTheme.warning100,
        AppTone.error => AppTheme.error100,
        AppTone.info => AppTheme.info100,
      };

  /// Text / icon color ON [surface].
  Color get onSurface => switch (this) {
        AppTone.neutral => AppTheme.neutral700,
        AppTone.primary => AppTheme.primary700,
        AppTone.success => AppTheme.success700,
        AppTone.warning => AppTheme.warning700,
        AppTone.error => AppTheme.error700,
        AppTone.info => AppTheme.info700,
      };

  /// A hairline around a tinted surface.
  Color get border => switch (this) {
        AppTone.neutral => AppTheme.neutral200,
        AppTone.primary => AppTheme.primary200,
        AppTone.success => AppTheme.success200,
        AppTone.warning => AppTheme.warning200,
        AppTone.error => AppTheme.error200,
        AppTone.info => AppTheme.info200,
      };

  /// The solid color: dots, bars, filled icons.
  Color get solid => switch (this) {
        AppTone.neutral => AppTheme.neutral400,
        AppTone.primary => AppTheme.primary500,
        AppTone.success => AppTheme.success500,
        AppTone.warning => AppTheme.warning500,
        AppTone.error => AppTheme.error500,
        AppTone.info => AppTheme.info500,
      };

  /// The softer track behind a [solid] progress bar.
  Color get track => switch (this) {
        AppTone.neutral => AppTheme.neutral200,
        AppTone.primary => AppTheme.primary100,
        AppTone.success => AppTheme.success100,
        AppTone.warning => AppTheme.warning100,
        AppTone.error => AppTheme.error100,
        AppTone.info => AppTheme.info100,
      };
}
