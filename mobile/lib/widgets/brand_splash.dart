import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's loading screen: the brand mark with a quiet spinner. One screen
/// for every wait at start-up (restoring the session, checking the account),
/// so the app does not flicker between different spinners on its way in.
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key, this.message});

  /// A short line under the spinner, e.g. "Checking your account…".
  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.ground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard + 6),
              ),
              child: Icon(AppIcons.send, size: 34, color: t.onFill),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: t.accent),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: t.subtle)),
            ],
          ],
        ),
      ),
    );
  }
}
