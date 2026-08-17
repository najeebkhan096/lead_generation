import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'excel_leads_page.dart';
import 'saved_businesses_page.dart';
import 'website_leads_page.dart';

/// The "Leads" bottom tab — three sources of businesses side by side: the
/// ones extracted from archived Excel scans, the ones saved straight to
/// Firestore's `leads` collection (bad reviews), and the ones saved to
/// `websiteLeads` (no website at all). Each sub-tab keeps its own page
/// (title, search, filters) intact; this just switches between them.
class LeadsPage extends StatelessWidget {
  const LeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusPill)),
                ),
                child: TabBar(
                  indicator: BoxDecoration(
                    color: t.accent,
                    borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusPill)),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: t.onFill,
                  unselectedLabelColor: t.subtle,
                  splashBorderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  tabs: const [
                    Tab(height: 40, text: 'Excel Sheet'),
                    Tab(height: 40, text: 'Direct'),
                    Tab(height: 40, text: 'Website'),
                  ],
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    ExcelLeadsPage(),
                    SavedBusinessesPage(),
                    WebsiteLeadsPage(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
