import 'package:flutter/material.dart';

import '../services/theme_controller.dart';
import '../theme/app_theme.dart';

/// App settings — currently the appearance (light / dark / system) choice.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App settings')),
      body: SafeArea(
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.mode,
          builder: (context, mode, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Text('Appearance',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  'Choose how the app looks, or let it follow your phone.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                _AppearanceOption(
                  mode: ThemeMode.system,
                  current: mode,
                  icon: AppIcons.monitor,
                  label: 'Match system',
                  hint: 'Follows your phone setting',
                ),
                _AppearanceOption(
                  mode: ThemeMode.light,
                  current: mode,
                  icon: AppIcons.sun,
                  label: 'Light',
                  hint: 'Warm cream, always',
                ),
                _AppearanceOption(
                  mode: ThemeMode.dark,
                  current: mode,
                  icon: AppIcons.moon,
                  label: 'Dark',
                  hint: 'Deep and cozy, easy on the eyes',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AppearanceOption extends StatelessWidget {
  const _AppearanceOption({
    required this.mode,
    required this.current,
    required this.icon,
    required this.label,
    required this.hint,
  });

  final ThemeMode mode;
  final ThemeMode current;
  final IconData icon;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final selected = mode == current;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? t.accentTint : t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
        child: InkWell(
          onTap: () => ThemeController.set(mode),
          borderRadius: BorderRadius.circular(AppTheme.radius + 4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? t.accent : t.neutralTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon,
                      size: 20, color: selected ? t.onFill : t.subtle),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: selected ? t.accentText : t.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(hint, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (selected)
                  Icon(AppIcons.circleCheck, size: 22, color: t.accentText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
