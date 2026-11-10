import 'package:flutter/widgets.dart';

import '../../core/theme/app_theme.dart';

/// One destination in the sidebar. Every item is a real route in
/// `app_router.dart`.
///
/// [branch] is the `StatefulShellRoute` branch for destinations that keep their
/// state when you navigate away (scroll position, filters, a running
/// validation); `null` for pages opened as plain routes. [alsoMatches] lists
/// sub-routes that should light this item up (e.g. a job's detail page).
class NavItem {
  const NavItem({
    required this.label,
    required this.icon,
    required this.path,
    this.branch,
    this.alsoMatches = const [],
    this.query = const {},
  });

  final String label;
  final IconData icon;
  final String path;
  final int? branch;
  final List<String> alsoMatches;

  /// Query parameters that tell items sharing a [path] apart (the two scan types).
  /// An empty value means "the parameter is absent".
  final Map<String, String> query;

  /// Where tapping this item goes.
  String get target {
    final params = {for (final e in query.entries) if (e.value.isNotEmpty) e.key: e.value};
    return params.isEmpty ? path : Uri(path: path, queryParameters: params).toString();
  }

  /// [location] is a path, optionally with a query string.
  bool matches(String location) {
    final uri = Uri.parse(location);
    for (final e in query.entries) {
      if ((uri.queryParameters[e.key] ?? '') != e.value) return false;
    }
    return _isUnder(path, uri.path) || alsoMatches.any((base) => _isUnder(base, uri.path));
  }
}

/// `/` matches only itself; any other [base] matches itself and its sub-routes.
bool _isUnder(String base, String location) =>
    base == '/' ? location == '/' : (location == base || location.startsWith('$base/'));

class NavGroup {
  const NavGroup(this.label, this.items);

  final String label;
  final List<NavItem> items;
}

/// The console's navigation, in the order the work happens.
final List<NavGroup> navGroups = [
  NavGroup('Overview', [
    NavItem(label: 'Dashboard', icon: AppIcons.dashboard, path: '/', branch: 0),
  ]),
  NavGroup('Lead generation', [
    NavItem(label: '1-Star Scan', icon: AppIcons.thumbsDown, path: '/scan', branch: 1, query: {'type': ''}, alsoMatches: ['/scan-progress', '/multi-scan']),
    NavItem(label: 'No-Website Scan', icon: AppIcons.search, path: '/scan', branch: 1, query: {'type': 'no-website'}),
    NavItem(label: 'Jobs Finder', icon: AppIcons.briefcase, path: '/jobs', branch: 10),
  ]),
  NavGroup('Leads', [
    NavItem(label: '1-Star Reviews', icon: AppIcons.thumbsDown, path: '/leads', branch: 3),
    NavItem(label: 'No Website', icon: AppIcons.globe, path: '/website-leads', branch: 8),
    NavItem(label: 'Email Leads', icon: AppIcons.mail, path: '/email-leads', branch: 9),
    NavItem(label: 'WhatsApp Verified', icon: AppIcons.shieldCheck, path: '/verified', branch: 4, alsoMatches: ['/whatsapp-verified']),
  ]),
  NavGroup('Management', [
    NavItem(label: 'Scan Archive', icon: AppIcons.inbox, path: '/archive', branch: 2),
    NavItem(label: 'Sales', icon: AppIcons.tag, path: '/sales', branch: 6),
    NavItem(label: 'Clients', icon: AppIcons.store, path: '/clients'),
    NavItem(label: 'Watchlist', icon: AppIcons.target, path: '/watchlist'),
    NavItem(label: 'Salesman Stats', icon: AppIcons.barChart, path: '/salesman-stats'),
  ]),
  NavGroup('System', [
    NavItem(label: 'WhatsApp Connection', icon: AppIcons.chat, path: '/whatsapp', branch: 7),
    NavItem(label: 'Users', icon: AppIcons.users, path: '/users'),
    NavItem(label: 'App Update', icon: AppIcons.download, path: '/app-update'),
    NavItem(label: 'Twilio Test', icon: AppIcons.send, path: '/twilio-test'),
    NavItem(label: 'More', icon: AppIcons.settings, path: '/more', branch: 5),
  ]),
];

/// The item to highlight for [location] (a path, optionally with a query): the
/// one whose path matches most specifically.
NavItem? navItemFor(String location) {
  final path = Uri.parse(location).path;
  NavItem? best;
  var bestLength = -1;
  for (final group in navGroups) {
    for (final item in group.items) {
      if (!item.matches(location)) continue;
      for (final base in [item.path, ...item.alsoMatches]) {
        if (_isUnder(base, path) && base.length > bestLength) {
          best = item;
          bestLength = base.length;
        }
      }
    }
  }
  return best;
}
