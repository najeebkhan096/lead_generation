import 'package:flutter/material.dart';

import '../services/app_update.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';

/// Shown instead of the app when this install is older than the minimum build.
/// It cannot be dismissed: the only way on is to install the new version.
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key, required this.rule, this.installedBuild});

  final AppUpdateRule rule;

  /// This install's build number, shown so a support call can confirm it.
  final int? installedBuild;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final hasLink = rule.apkUrl.isNotEmpty;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: t.accentTint, borderRadius: BorderRadius.circular(AppTheme.radius)),
                    child: Icon(AppIcons.download, size: 30, color: t.accentText),
                  ),
                  const SizedBox(height: 22),
                  Text('Update required', style: text.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(rule.message, style: text.bodyLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(
                    installedBuild == null
                        ? 'Version ${rule.latestBuild} is needed.'
                        : 'This is build $installedBuild. Build ${rule.latestBuild} is needed.',
                    style: text.bodySmall?.copyWith(color: t.faint),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: hasLink ? () => openExternalUrl(rule.apkUrl) : null,
                    icon: const Icon(AppIcons.download, size: 18),
                    label: const Text('Download the update'),
                  ),
                  if (!hasLink) ...[
                    const SizedBox(height: 12),
                    Text(
                      'The download link is not set yet. Ask your admin for the new version.',
                      style: text.bodySmall?.copyWith(color: t.danger),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
