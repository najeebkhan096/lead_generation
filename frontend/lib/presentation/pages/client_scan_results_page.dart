import 'package:flutter/material.dart';

import '../../domain/entities/sale.dart';
import 'client_review_scan_page.dart';

/// Result of a Clients-page scan: the 1★ reviews found in the chosen window.
class ClientScanResultsPage extends StatelessWidget {
  const ClientScanResultsPage({super.key, required this.results, required this.days});

  final List<SaleReviewScanResult> results;
  final int days;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('1★ reviews · last $days days')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ScanResultsView(results: results, days: days),
          ),
        ),
      ),
    );
  }
}
