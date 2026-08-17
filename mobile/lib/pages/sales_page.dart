import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../services/open_links.dart';
import '../services/sale_repository.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/page_header.dart';
import '../widgets/search_field.dart';
import 'saved_businesses_page.dart' show StateBadge;

/// A salesman's own orders — mirrors the web admin's Sales dashboard, but
/// scoped to just this user's sales and stripped down to what a salesman
/// needs to see: order status and their own payout, not client billing or
/// profit. Payment status/amounts are set by admins on the web app; this
/// page is read-only.
class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _repo = SaleRepository();
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Stream<List<Sale>>? _salesStream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _salesStream = _repo.getSalesStream(uid);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (_salesStream == null) {
      return const Scaffold(body: SafeArea(child: _ScrollableCenter(child: _SignedOutState())));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: StreamBuilder<List<Sale>>(
            stream: _salesStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ScrollableCenter(
                  child: _ErrorState(message: snapshot.error.toString(), onRetry: () async => setState(() {})),
                );
              }

              final allSales = snapshot.data ?? const <Sale>[];

              var ongoing = allSales
                  .where((s) => s.status == SaleStatus.newSale || s.status == SaleStatus.inProgress)
                  .toList();
              var completed = allSales
                  .where((s) => s.status == SaleStatus.completed || s.status == SaleStatus.cancelled)
                  .toList();

              if (_searchQuery.isNotEmpty) {
                final query = _searchQuery.toLowerCase();
                bool matches(Sale s) => s.businessName.toLowerCase().contains(query);
                ongoing = ongoing.where(matches).toList();
                completed = completed.where(matches).toList();
              }

              final totalEarned = allSales
                  .where((s) => s.employeePaymentStatus == EmployeePaymentStatus.paid)
                  .fold<double>(0, (sum, s) => sum + s.employeePaymentAmount);
              final pending = allSales
                  .where((s) => s.status == SaleStatus.completed && s.employeePaymentStatus == EmployeePaymentStatus.pending)
                  .fold<double>(0, (sum, s) => sum + s.employeePaymentAmount);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'My Sales',
                    subtitle: allSales.isEmpty ? 'Orders assigned to you will show up here' : '${allSales.length} total ${allSales.length == 1 ? 'order' : 'orders'}',
                    trailing: HeaderBadge(icon: AppIcons.wallet, background: t.sageTint, foreground: t.sageDeep),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SearchField(
                      controller: _searchController,
                      value: _searchQuery,
                      hintText: 'Search orders...',
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _EarningsTile(
                          label: 'Total earned',
                          amountPkr: totalEarned,
                          icon: AppIcons.wallet,
                          background: t.sage,
                          foreground: t.onFill,
                        ),
                        const SizedBox(width: 10),
                        _EarningsTile(
                          label: 'Pending payment',
                          amountPkr: pending,
                          icon: AppIcons.hourglass,
                          background: t.accentTint,
                          foreground: t.accentTextStrong,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _SegmentedTabs(),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _SaleList(sales: ongoing, emptyMessage: 'No ongoing orders'),
                        _SaleList(sales: completed, emptyMessage: 'No completed orders yet'),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: t.surface, borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusPill))),
      child: TabBar(
        indicator: BoxDecoration(color: t.accent, borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusPill))),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: t.onFill,
        unselectedLabelColor: t.subtle,
        splashBorderRadius: BorderRadius.circular(AppTheme.radiusPill),
        tabs: const [
          Tab(height: 40, text: 'Ongoing'),
          Tab(height: 40, text: 'Completed'),
        ],
      ),
    );
  }
}

class _EarningsTile extends StatelessWidget {
  const _EarningsTile({
    required this.label,
    required this.amountPkr,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final double amountPkr;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.radius + 4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(height: 8),
            Text(
              'Rs ${_formatAmount(amountPkr)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: foreground)),
          ],
        ),
      ),
    );
  }

  static String _formatAmount(double amount) {
    final rounded = amount.round();
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return (rounded < 0 ? '-' : '') + buffer.toString();
  }
}

class _SaleList extends StatelessWidget {
  const _SaleList({required this.sales, required this.emptyMessage});

  final List<Sale> sales;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return _ScrollableCenter(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StateBadge(icon: AppIcons.wallet),
            const SizedBox(height: 20),
            Text(emptyMessage, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      itemCount: sales.length,
      itemBuilder: (context, i) => _SaleCard(sale: sales[i]),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final date = formatDate(sale.updatedAt ?? sale.createdAt);
    final (statusLabel, statusBg, statusFg) = switch (sale.status) {
      SaleStatus.newSale => ('NEW', t.neutralTint, t.subtle),
      SaleStatus.inProgress => ('IN PROGRESS', t.accentTint, t.accentTextStrong),
      SaleStatus.completed => ('COMPLETED', t.sage, t.onFill),
      SaleStatus.cancelled => ('CANCELLED', t.neutralTintStrong, t.faint),
    };
    final paid = sale.employeePaymentStatus == EmployeePaymentStatus.paid;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard), border: Border.all(color: t.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sale.businessName,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                child: Text(statusLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: statusFg)),
              ),
            ],
          ),
          if (date != null) ...[
            const SizedBox(height: 4),
            Text(date, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(AppIcons.wallet, size: 15, color: paid ? t.sageDeep : t.accentText),
              const SizedBox(width: 6),
              Text(
                'Rs ${_EarningsTile._formatAmount(sale.employeePaymentAmount)}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: t.ink),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: paid ? t.sageTint : t.accentTint,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  sale.employeePaymentStatus.label,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: paid ? t.sageTextStrong : t.accentTextStrong),
                ),
              ),
              const Spacer(),
              if (sale.reviewLink != null && sale.reviewLink!.trim().isNotEmpty)
                _RoundIconButton(onTap: () => openExternalUrl(sale.reviewLink!)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.neutralTint,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(AppIcons.externalLink, size: 16, color: t.subtle),
        ),
      ),
    );
  }
}

class _ScrollableCenter extends StatelessWidget {
  const _ScrollableCenter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: Padding(padding: const EdgeInsets.all(28), child: child)),
          ),
        );
      },
    );
  }
}

class _SignedOutState extends StatelessWidget {
  const _SignedOutState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const StateBadge(icon: AppIcons.wallet),
        const SizedBox(height: 20),
        Text('Sign in to see your sales', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StateBadge(icon: AppIcons.alert, background: t.accentTint, foreground: t.accentText),
        const SizedBox(height: 20),
        Text('Could not load sales', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: t.danger)),
        const SizedBox(height: 20),
        OutlinedButton.icon(onPressed: onRetry, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
      ],
    );
  }
}
