import 'package:flutter/material.dart';

import '../services/admin_data.dart';
import '../services/admin_repository.dart';
import '../theme/app_theme.dart';
import 'admin_clients_page.dart';
import 'admin_more_page.dart';
import 'admin_overview_page.dart';
import 'admin_sales_page.dart';
import 'admin_salesmen_page.dart';

/// The admin console: five destinations over one shared [AdminData] load.
///
///   Overview  |  Salesmen  |  Sales  |  Clients  |  More
///
/// Every tab stays built (IndexedStack) so each keeps its search, filter and
/// scroll position while the admin moves around.
class AdminNavigationPage extends StatefulWidget {
  const AdminNavigationPage({super.key, this.repository});

  /// Overridable for tests; the app uses the REST-backed default.
  final AdminRepository? repository;

  @override
  State<AdminNavigationPage> createState() => _AdminNavigationPageState();
}

class _AdminNavigationPageState extends State<AdminNavigationPage> {
  late final AdminData _data = AdminData(repository: widget.repository);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _data.load();
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScope(
      data: _data,
      child: Builder(
        builder: (context) {
          final pending = AdminScope.of(context).snapshot.pendingApprovals;
          return Scaffold(
            body: IndexedStack(
              index: _index,
              children: [
                AdminOverviewPage(onOpenTab: (i) => setState(() => _index = i)),
                const AdminSalesmenPage(),
                const AdminSalesPage(),
                const AdminClientsPage(),
                const AdminMorePage(),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                const NavigationDestination(icon: Icon(AppIcons.dashboard), label: 'Overview'),
                NavigationDestination(
                  icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(AppIcons.users)),
                  label: 'Salesmen',
                ),
                const NavigationDestination(icon: Icon(AppIcons.clipboardList), label: 'Sales'),
                const NavigationDestination(icon: Icon(AppIcons.store), label: 'Clients'),
                const NavigationDestination(icon: Icon(AppIcons.more), label: 'More'),
              ],
            ),
          );
        },
      ),
    );
  }
}
