import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/prefs_storage.dart';
import '../../core/theme/theme_controller.dart';
import 'nav_model.dart';

const double sidebarExpandedWidth = 256;
const double sidebarCollapsedWidth = 68;

/// Whether the user has collapsed the sidebar (`null` = follow the window
/// size). Remembered in the browser.
class SidebarPrefs {
  SidebarPrefs._();

  static const _key = 'leadfinder.sidebarCollapsed';

  static final ValueNotifier<bool?> collapsed = ValueNotifier<bool?>(
    switch (PrefsStorage.read(_key)) {
      'true' => true,
      'false' => false,
      _ => null,
    },
  );

  static void set(bool value) {
    collapsed.value = value;
    PrefsStorage.write(_key, '$value');
  }
}

/// The navigation rail. Always navy (in both themes), grouped, collapsible to
/// an icon rail, with the theme switch and the profile at the bottom.
///
/// The content is laid out once at full width and clipped as the rail narrows,
/// so icons never move while it animates.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.collapsed,
    this.onToggleCollapsed,
    this.inDrawer = false,
  });

  final NavItem? selected;
  final ValueChanged<NavItem> onSelect;
  final bool collapsed;

  /// `null` hides the collapse control (the drawer is always expanded).
  final VoidCallback? onToggleCollapsed;
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: collapsed ? 0.0 : 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final width =
            sidebarCollapsedWidth +
            (sidebarExpandedWidth - sidebarCollapsedWidth) * t;
        return Container(
          width: inDrawer ? sidebarExpandedWidth : width,
          decoration: BoxDecoration(
            color: AppTheme.sidebar,
            border: AppTheme.isDark
                ? Border(right: BorderSide(color: AppTheme.sidebarSurface))
                : null,
          ),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: sidebarExpandedWidth,
              maxWidth: sidebarExpandedWidth,
              child: _SidebarBody(
                t: inDrawer ? 1 : t,
                selected: selected,
                onSelect: onSelect,
                onToggleCollapsed: onToggleCollapsed,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SidebarBody extends StatelessWidget {
  const _SidebarBody({
    required this.t,
    required this.selected,
    required this.onSelect,
    required this.onToggleCollapsed,
  });

  /// 0 = collapsed rail, 1 = fully expanded.
  final double t;
  final NavItem? selected;
  final ValueChanged<NavItem> onSelect;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeController.of(context);
    return SafeArea(
      child: Column(
        children: [
          _Brand(t: t),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              children: [
                for (final group in navGroups) ...[
                  _GroupLabel(group.label, t: t),
                  for (final item in group.items)
                    _SidebarItem(
                      icon: item.icon,
                      label: item.label,
                      selected: item == selected,
                      t: t,
                      onTap: () => onSelect(item),
                    ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.sidebarSurface),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              children: [
                ListenableBuilder(
                  listenable: themeController,
                  builder: (context, _) => _SidebarItem(
                    icon: themeController.isDark ? AppIcons.sun : AppIcons.moon,
                    label: themeController.isDark ? 'Light mode' : 'Dark mode',
                    t: t,
                    onTap: themeController.toggle,
                  ),
                ),
                if (onToggleCollapsed != null)
                  _SidebarItem(
                    icon: AppIcons.panelLeft,
                    label: t > 0.5 ? 'Collapse sidebar' : 'Expand sidebar',
                    t: t,
                    onTap: onToggleCollapsed!,
                  ),
              ],
            ),
          ),
          _Profile(t: t),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.only(left: 18),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primary500,
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
              child: Icon(AppIcons.target, size: 18, color: AppTheme.onPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: t,
                child: Text(
                  'LeadFinder',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSidebar,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, {required this.t});

  final String label;
  final double t;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Stack(
        children: [
          // Collapsed: a short rule; expanded: the group's name.
          Positioned(
            left: 12,
            right: 12,
            bottom: 6,
            child: Opacity(
              opacity: 1 - t,
              child: Divider(height: 1, color: AppTheme.sidebarSurface),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 6,
            child: Opacity(
              opacity: t,
              child: Text(
                label.toUpperCase(),
                softWrap: false,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppTheme.onSidebarMuted.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.t,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final double t;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final fg = selected
        ? AppTheme.onPrimary
        : (_hover ? AppTheme.onSidebar : AppTheme.onSidebarMuted);
    final bg = selected
        ? AppTheme.sidebarSurface
        : (_hover
              ? AppTheme.sidebarSurface.withValues(alpha: 0.55)
              : Colors.transparent);

    final item = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Stack(
              children: [
                if (selected)
                  Positioned(
                    left: 0,
                    top: 8,
                    bottom: 8,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: AppTheme.sidebarIndicator,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Row(
                    children: [
                      // 12px item margin + 12px here puts the icon's centre at x=34,
                      // the middle of the 68px collapsed rail.
                      const SizedBox(width: 12),
                      Icon(
                        widget.icon,
                        size: 18,
                        color: selected ? AppTheme.sidebarAccent : fg,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Opacity(
                          opacity: widget.t,
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: fg,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return widget.t < 0.5 ? Tooltip(message: widget.label, preferBelow: false, child: item) : item;
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.only(left: 18),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.sidebarSurface,
              shape: BoxShape.circle,
            ),
            child: Text(
              'A',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.onSidebar,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Opacity(
              opacity: t,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin',
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSidebar,
                    ),
                  ),
                  Text(
                    'LeadFinder console',
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.onSidebarMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
