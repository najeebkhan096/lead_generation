import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A mobile user's photo, falling back to their initial.
///
/// Google profile photos are rate limited (HTTP 429 when many are fetched at
/// once) and can disappear; a failed load must show the initial rather than
/// throw an unhandled image exception.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.photoUrl, this.radius = 20});

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = Text(
      trimmed.isEmpty ? '?' : String.fromCharCode(trimmed.runes.first).toUpperCase(),
      style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.accent700),
    );
    final url = photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.accent100,
      child: url == null || url.isEmpty
          ? initial
          : ClipOval(
              child: Image.network(
                url,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => initial,
              ),
            ),
    );
  }
}
