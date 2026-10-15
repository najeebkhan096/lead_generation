import 'package:flutter/material.dart';

import '../widgets/segmented_tab_bar.dart';
import 'excel_leads_page.dart';
import 'saved_businesses_page.dart';
import 'website_leads_page.dart';

/// The "Leads" bottom tab — what a scan found, in three views: the
/// businesses in archived Excel scans ("Scans"), the saved 1-star review
/// leads ("1-star", Firestore `leads`) and the saved no-website leads
/// ("No website", `websiteLeads`). Each sub-tab keeps its own page (title,
/// search, filters) intact; this just switches between them.
class LeadsPage extends StatelessWidget {
  const LeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const SegmentedTabBar(
                margin: EdgeInsets.fromLTRB(20, 16, 20, 0),
                labels: ['Scans', '1-star', 'No website'],
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
