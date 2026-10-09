import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sales_user.dart';
import '../../domain/entities/watchlist_entry.dart';
import '../../domain/repositories/lead_repository.dart';
import 'client_review_scan_page.dart';

const _allSalesmen = 'All salesmen';

String _formatAmount(double value) {
  final isNegative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${isNegative ? '-' : ''}$buffer.${parts[1]}';
}

/// USD — what clients are billed.
String usd(double value) => '\$${_formatAmount(value)}';

/// PKR — everything on the operations side (employee payout, client amount
/// actually received after conversion, removal cost, profit). Deliberately
/// a different formatter from [usd] so the two currencies are never
/// visually confusable, let alone summed together.
String pkr(double value) => 'PKR ${_formatAmount(value)}';

(Color, Color, IconData) leadStatusStyle(LeadStatus status) {
  switch (status) {
    case LeadStatus.newLead:
      return (AppTheme.neutral600, AppTheme.neutral100, AppIcons.sparkles);
    case LeadStatus.inProgress:
      return (AppTheme.accent700, AppTheme.accent100, AppIcons.zap);
    case LeadStatus.completed:
      return (AppTheme.sage800, AppTheme.sage100, AppIcons.shieldCheck);
    case LeadStatus.cancelled:
      return (AppTheme.neutral600, AppTheme.neutral100, AppIcons.close);
  }
}

(Color, Color) clientPaymentStyle(ClientPaymentStatus status) {
  switch (status) {
    case ClientPaymentStatus.pending:
      return (AppTheme.neutral600, AppTheme.neutral100);
    case ClientPaymentStatus.paid:
    case ClientPaymentStatus.received:
      return (AppTheme.sage700, AppTheme.sage100);
    case ClientPaymentStatus.stuck:
      return (AppTheme.danger, AppTheme.accent100);
    case ClientPaymentStatus.inProcess:
      return (AppTheme.accent700, AppTheme.accent100);
  }
}

(Color, Color) employeePaymentStyle(EmployeePaymentStatus status) {
  return status == EmployeePaymentStatus.paid
      ? (AppTheme.sage700, AppTheme.sage100)
      : (AppTheme.neutral600, AppTheme.neutral100);
}

/// Sales: Ongoing and Completed deal lists plus a Team roster. One shared
/// salesman filter drives the lists. Each sale shows only what's needed —
/// who, status, what the client pays, what the salesman is paid.
class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 4, vsync: this);
  List<SalesUser> _salesmen = [];
  bool _loadingSalesmen = true;
  String? _salesmenError;
  String _filterSalesmanId = _allSalesmen;
  bool _scanningReviews = false;
  List<SaleReviewScanResult> _reviewScanResults = [];

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _loadSalesmen();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSalesmen() async {
    setState(() {
      _loadingSalesmen = true;
      _salesmenError = null;
    });
    try {
      final salesmen = await _repo.listSalesmen();
      if (!mounted) return;
      setState(() {
        _salesmen = salesmen;
        _loadingSalesmen = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSalesmen = false;
        _salesmenError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _scanSaleReviews() async {
    if (_scanningReviews) return;
    setState(() {
      _scanningReviews = true;
      _reviewScanResults = [];
    });
    try {
      final salesmanId = _filterSalesmanId == _allSalesmen ? null : _filterSalesmanId;
      final results = await _repo.scanSaleReviews(dateRange: '30', salesmanId: salesmanId);
      if (!mounted) return;
      final flagged = results.where((r) => r.newReviews.isNotEmpty).length;
      final skipped = results.where((r) => r.skipped).length;
      setState(() => _reviewScanResults = results);
      final String message;
      if (flagged > 0) {
        message = '$flagged business${flagged == 1 ? '' : 'es'} with 1★ reviews in the last 30 days.';
      } else if (results.isEmpty) {
        message = 'No ongoing or completed sales to scan.';
      } else if (skipped == results.length) {
        message = 'Add a Google Maps review link on each sale first.';
      } else {
        message = 'No 1★ reviews in the last 30 days.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _scanningReviews = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final salesmanId = _filterSalesmanId == _allSalesmen ? null : _filterSalesmanId;
    final scanById = {for (final r in _reviewScanResults) r.id: r};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterSalesmanId,
                icon: const Icon(AppIcons.chevronDown, size: 16, color: AppTheme.subtle),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.ink),
                items: [
                  const DropdownMenuItem(value: _allSalesmen, child: Text(_allSalesmen)),
                  for (final s in _salesmen) DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _filterSalesmanId = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _scanningReviews ? null : _scanSaleReviews,
            icon: _scanningReviews
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(AppIcons.star, size: 18),
            label: Text(_scanningReviews ? 'Scanning…' : 'Scan 1★'),
          ),
          const SizedBox(width: 12),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Ongoing'),
            Tab(text: 'Completed'),
            Tab(text: 'Clients'),
            Tab(text: 'Team'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _SalesListTab(
            salesmanId: salesmanId,
            ongoing: true,
            salesmen: _salesmen,
            scanning: _scanningReviews,
            scanById: scanById,
          ),
          _SalesListTab(
            salesmanId: salesmanId,
            ongoing: false,
            salesmen: _salesmen,
            scanning: _scanningReviews,
            scanById: scanById,
          ),
          const _ClientsTab(),
          _TeamTab(
            salesmen: _salesmen,
            loading: _loadingSalesmen,
            error: _salesmenError,
            onRetry: _loadSalesmen,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Clients: every business we have sold to, once
// ---------------------------------------------------------------------------

/// One client business, merged from all of its sales.
class ClientBusiness {
  const ClientBusiness({required this.name, required this.mapsUrl, required this.dealCount});

  final String name;

  /// Google Maps / review link from any of its sales; null when none has one.
  final String? mapsUrl;
  final int dealCount;

  /// Opens the saved link, or falls back to a Google Maps search by name.
  Uri get uri => Uri.parse(
        mapsUrl ?? 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeQueryComponent(name)}',
      );
}

String _clientKey(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r"['’`]"), '') // "Joe's" == "Joes"
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// Collapses sales into unique clients (same business name, ignoring case and
/// punctuation), sorted by name.
List<ClientBusiness> uniqueClients(List<Sale> sales) {
  final byKey = <String, ({String name, String? url, int count})>{};
  for (final s in sales) {
    final name = s.businessName.trim();
    final key = _clientKey(name);
    if (key.isEmpty) continue;
    final link = s.reviewLink?.trim();
    final prev = byKey[key];
    byKey[key] = (
      name: prev?.name ?? name,
      url: prev?.url ?? ((link != null && link.isNotEmpty) ? link : null),
      count: (prev?.count ?? 0) + 1,
    );
  }
  return [
    for (final e in byKey.values) ClientBusiness(name: e.name, mapsUrl: e.url, dealCount: e.count),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

class _ClientsTab extends StatefulWidget {
  const _ClientsTab();

  @override
  State<_ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends State<_ClientsTab> with AutomaticKeepAliveClientMixin {
  List<ClientBusiness> _clients = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sales = await context.read<LeadRepository>().listSales();
      if (!mounted) return;
      setState(() {
        _clients = uniqueClients(sales);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: AppTheme.danger)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? _clients : _clients.where((c) => c.name.toLowerCase().contains(q)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(AppIcons.search, size: 18),
                  hintText: 'Search ${_clients.length} clients',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _clients.isEmpty
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClientReviewScanPage())),
              icon: const Icon(AppIcons.star, size: 18),
              label: const Text('Scan 1★'),
            ),
          ]),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(_clients.isEmpty ? 'No clients yet' : 'No clients match your search'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = shown[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          onTap: () => launchUrl(c.uri, mode: LaunchMode.externalApplication),
                          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${c.dealCount} ${c.dealCount == 1 ? 'sale' : 'sales'}'
                            '${c.mapsUrl == null ? ' · opens a Maps search' : ''}',
                          ),
                          trailing: const Icon(AppIcons.mapPin, size: 20, color: AppTheme.accent700),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ongoing / Completed list
// ---------------------------------------------------------------------------

class _SalesListTab extends StatefulWidget {
  const _SalesListTab({
    required this.salesmanId,
    required this.ongoing,
    required this.salesmen,
    required this.scanning,
    required this.scanById,
  });

  final String? salesmanId;

  /// True = new + in progress; false = completed + cancelled.
  final bool ongoing;
  final List<SalesUser> salesmen;
  final bool scanning;
  final Map<String, SaleReviewScanResult> scanById;

  @override
  State<_SalesListTab> createState() => _SalesListTabState();
}

class _SalesListTabState extends State<_SalesListTab> with AutomaticKeepAliveClientMixin {
  List<Sale> _sales = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SalesListTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.salesmanId != widget.salesmanId) _load();
    if (oldWidget.scanning && !widget.scanning) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sales = await context.read<LeadRepository>().listSales(salesmanId: widget.salesmanId);
      if (!mounted) return;
      setState(() {
        _sales = sales.where((s) {
          final isOngoing = s.leadStatus == LeadStatus.newLead || s.leadStatus == LeadStatus.inProgress;
          return isOngoing == widget.ongoing;
        }).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openForm({Sale? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _SaleFormDialog(sale: existing, salesmen: widget.salesmen),
    );
    if (result == true) await _load();
  }

  Future<void> _delete(Sale sale) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this sale?'),
        content: Text('"${sale.businessName}" will be permanently removed. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await context.read<LeadRepository>().deleteSale(sale.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_sales.length} ${widget.ongoing ? 'ongoing' : 'completed'} sale${_sales.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 12.5, color: AppTheme.faint, fontWeight: FontWeight.w700),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: () => _openForm(),
                            icon: const Icon(AppIcons.plus, size: 18),
                            label: const Text('New Sale'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_sales.isEmpty)
                        _EmptyState(widget.ongoing ? 'No ongoing sales' : 'No completed sales')
                      else
                        for (final sale in _sales)
                          _SaleCard(
                            sale: sale,
                            scanResult: widget.scanById[sale.id],
                            onEdit: () => _openForm(existing: sale),
                            onDelete: () => _delete(sale),
                          ),
                    ],
                  ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(child: Text(message, style: const TextStyle(fontSize: 13, color: AppTheme.faint))),
    );
  }
}

// ---------------------------------------------------------------------------
// Sale card
// ---------------------------------------------------------------------------

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale, this.onEdit, this.onDelete, this.scanResult});

  final Sale sale;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final SaleReviewScanResult? scanResult;

  @override
  Widget build(BuildContext context) {
    final (leadColor, leadBg, leadIcon) = leadStatusStyle(sale.leadStatus);
    final (clientColor, clientBg) = clientPaymentStyle(sale.clientPaymentStatus);
    final (empColor, empBg) = employeePaymentStyle(sale.employeePaymentStatus);
    final newReviews = scanResult?.newReviews ?? const <WatchlistReview>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: newReviews.isNotEmpty ? AppTheme.accent300 : AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sale.businessName, style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(AppIcons.users, size: 12, color: AppTheme.faint),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            sale.salesmanName ?? 'Unassigned',
                            style: const TextStyle(fontSize: 12.5, color: AppTheme.faint, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (sale.reviewLink != null && sale.reviewLink!.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () => launchUrl(Uri.parse(sale.reviewLink!)),
                            child: const Icon(AppIcons.externalLink, size: 13, color: AppTheme.faint),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(icon: leadIcon, label: sale.leadStatus.label, color: leadColor, background: leadBg),
              if (onEdit != null)
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(AppIcons.edit, size: 17, color: AppTheme.faint),
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(AppIcons.trash, size: 17, color: AppTheme.faint),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _MoneyLine(
                  label: 'Client',
                  amount: usd(sale.priceChargedToClient),
                  status: sale.clientPaymentStatus.label,
                  color: clientColor,
                  background: clientBg,
                ),
                _MoneyLine(
                  label: 'Salesman',
                  amount: pkr(sale.employeePaymentAmount),
                  status: sale.employeePaymentStatus.label,
                  color: empColor,
                  background: empBg,
                ),
              ],
            ),
          ),
          if (newReviews.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${newReviews.length} new 1★ review${newReviews.length == 1 ? '' : 's'} in the last 30 days',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.accent700),
            ),
            const SizedBox(height: 8),
            for (final review in newReviews) _SaleReviewTile(review: review),
          ],
        ],
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({required this.label, required this.amount, required this.status, required this.color, required this.background});

  final String label;
  final String amount;
  final String status;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label  ', style: const TextStyle(fontSize: 12.5, color: AppTheme.faint)),
        Text(amount, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.ink)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
          child: Text(status, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label, required this.color, required this.background});

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _SaleReviewTile extends StatelessWidget {
  const _SaleReviewTile({required this.review});

  final WatchlistReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(AppIcons.star, size: 15, color: AppTheme.accent700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${review.reviewer} · ${review.stars ?? '?'}★ · ${review.date}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.subtle),
                      ),
                    ),
                    if (review.link != null)
                      InkWell(
                        onTap: () => launchUrl(Uri.parse(review.link!)),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'Open',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (review.text.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(review.text, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team tab
// ---------------------------------------------------------------------------

/// Every salesman (mobile app account, role `salesman`) available to assign
/// sales to. Read-only: the roster grows as people sign into the mobile app.
class _TeamTab extends StatelessWidget {
  const _TeamTab({required this.salesmen, required this.loading, this.error, required this.onRetry});

  final List<SalesUser> salesmen;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (salesmen.isEmpty) {
      return const _EmptyState('No salesmen yet — they appear here once someone signs into the mobile app.');
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            for (final s in salesmen)
              _SalesmanCard(
                salesman: s,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _SalesmanDetailPage(salesman: s)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SalesmanCard extends StatelessWidget {
  const _SalesmanCard({required this.salesman, required this.onTap});

  final SalesUser salesman;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _Avatar(salesman, radius: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(salesman.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (salesman.email != null && salesman.email!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(salesman.email!, style: const TextStyle(fontSize: 12, color: AppTheme.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const Icon(AppIcons.chevronRight, size: 16, color: AppTheme.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.salesman, {required this.radius});

  final SalesUser salesman;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = salesman.photoURL != null && salesman.photoURL!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.accent100,
      backgroundImage: hasPhoto ? NetworkImage(salesman.photoURL!) : null,
      child: hasPhoto
          ? null
          : Text(
              salesman.name.trim().isEmpty ? '?' : salesman.name.trim()[0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.accent700),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Salesman detail page
// ---------------------------------------------------------------------------

class _SalesmanDetailPage extends StatefulWidget {
  const _SalesmanDetailPage({required this.salesman});

  final SalesUser salesman;

  @override
  State<_SalesmanDetailPage> createState() => _SalesmanDetailPageState();
}

class _SalesmanDetailPageState extends State<_SalesmanDetailPage> {
  List<Sale> _sales = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sales = await context.read<LeadRepository>().listSales(salesmanId: widget.salesman.id);
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final owed = _sales
        .where((s) => s.employeePaymentStatus == EmployeePaymentStatus.pending)
        .fold<double>(0, (a, s) => a + s.employeePaymentAmount);
    final paid = _sales
        .where((s) => s.employeePaymentStatus == EmployeePaymentStatus.paid)
        .fold<double>(0, (a, s) => a + s.employeePaymentAmount);

    return Scaffold(
      appBar: AppBar(title: Text(widget.salesman.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(onPressed: _load, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
                    ],
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _PayoutTile(
                                label: 'Still owed',
                                value: pkr(owed),
                                icon: AppIcons.alert,
                                color: AppTheme.danger,
                                background: AppTheme.accent100,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _PayoutTile(
                                label: 'Already paid',
                                value: pkr(paid),
                                icon: AppIcons.checkCircle,
                                color: AppTheme.sage700,
                                background: AppTheme.sage100,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (_sales.isEmpty)
                          _EmptyState('${widget.salesman.name} isn\'t assigned to any sale yet.')
                        else
                          for (final sale in _sales) _SaleCard(sale: sale),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _PayoutTile extends StatelessWidget {
  const _PayoutTile({required this.label, required this.value, required this.icon, required this.color, required this.background});

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New / edit form
// ---------------------------------------------------------------------------

class _SaleFormDialog extends StatefulWidget {
  const _SaleFormDialog({this.sale, required this.salesmen});

  final Sale? sale;
  final List<SalesUser> salesmen;

  @override
  State<_SaleFormDialog> createState() => _SaleFormDialogState();
}

class _SaleFormDialogState extends State<_SaleFormDialog> {
  late final _businessController = TextEditingController(text: widget.sale?.businessName ?? '');
  late final _linkController = TextEditingController(text: widget.sale?.reviewLink ?? '');
  late final _priceController =
      TextEditingController(text: widget.sale == null ? '' : widget.sale!.priceChargedToClient.toStringAsFixed(2));
  late final _employeeAmountController =
      TextEditingController(text: widget.sale == null ? '' : widget.sale!.employeePaymentAmount.toStringAsFixed(2));

  late String? _salesmanId = widget.sale?.salesmanId;
  late LeadStatus _leadStatus = widget.sale?.leadStatus ?? LeadStatus.newLead;
  late ClientPaymentStatus _clientPaymentStatus = widget.sale?.clientPaymentStatus ?? ClientPaymentStatus.pending;
  late EmployeePaymentStatus _employeePaymentStatus = widget.sale?.employeePaymentStatus ?? EmployeePaymentStatus.pending;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _businessController.dispose();
    _linkController.dispose();
    _priceController.dispose();
    _employeeAmountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final businessName = _businessController.text.trim();
    if (businessName.isEmpty) {
      setState(() => _error = 'Business name is required');
      return;
    }
    final link = _linkController.text.trim();
    if (link.isNotEmpty && !(Uri.tryParse(link)?.hasScheme ?? false)) {
      setState(() => _error = 'Enter the full Google Maps link (starting with https://)');
      return;
    }
    final priceText = _priceController.text.trim();
    if (priceText.isNotEmpty && (double.tryParse(priceText) ?? -1) < 0) {
      setState(() => _error = 'Enter a valid price');
      return;
    }
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final employeeAmount = double.tryParse(_employeeAmountController.text.trim()) ?? 0;
    final salesman = widget.salesmen.where((s) => s.id == _salesmanId).firstOrNull;
    final reviewLink = _linkController.text.trim().isEmpty ? null : _linkController.text.trim();

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = context.read<LeadRepository>();
      if (widget.sale == null) {
        await repo.createSale(
          businessName: businessName,
          reviewLink: reviewLink,
          salesmanId: salesman?.id,
          salesmanName: salesman?.name,
          leadStatus: _leadStatus,
          priceChargedToClient: price,
          clientPaymentStatus: _clientPaymentStatus,
          employeePaymentAmount: employeeAmount,
          employeePaymentStatus: _employeePaymentStatus,
        );
      } else {
        await repo.updateSale(
          widget.sale!.id,
          businessName: businessName,
          reviewLink: reviewLink,
          salesmanId: salesman?.id,
          salesmanName: salesman?.name,
          leadStatus: _leadStatus,
          priceChargedToClient: price,
          clientPaymentStatus: _clientPaymentStatus,
          employeePaymentAmount: employeeAmount,
          employeePaymentStatus: _employeePaymentStatus,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.sale == null ? 'New Sale' : 'Edit Sale'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _businessController,
                decoration: const InputDecoration(labelText: 'Business name'),
                textCapitalization: TextCapitalization.words,
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _linkController,
                decoration: const InputDecoration(labelText: 'Google Maps link', hintText: 'https://maps.app.goo.gl/...'),
                keyboardType: TextInputType.url,
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _salesmanId,
                      decoration: const InputDecoration(labelText: 'Salesman'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                        for (final s in widget.salesmen) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _salesmanId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(labelText: 'Client pays', prefixText: '\$'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      enabled: !_saving,
                    ),
                  ),
                ],
              ),
              // Status and payment tracking only matter once the sale exists.
              if (widget.sale != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<LeadStatus>(
                  initialValue: _leadStatus,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [for (final s in LeadStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                  onChanged: _saving ? null : (v) => setState(() => _leadStatus = v ?? _leadStatus),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ClientPaymentStatus>(
                  initialValue: _clientPaymentStatus,
                  decoration: const InputDecoration(labelText: 'Client payment'),
                  items: [for (final s in ClientPaymentStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                  onChanged: _saving ? null : (v) => setState(() => _clientPaymentStatus = v ?? _clientPaymentStatus),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _employeeAmountController,
                        decoration: const InputDecoration(labelText: 'Salesman gets', prefixText: 'PKR '),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        enabled: !_saving,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<EmployeePaymentStatus>(
                        initialValue: _employeePaymentStatus,
                        decoration: const InputDecoration(labelText: 'Salesman payment'),
                        items: [for (final s in EmployeePaymentStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
                        onChanged: _saving ? null : (v) => setState(() => _employeePaymentStatus = v ?? _employeePaymentStatus),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface))
              : Text(widget.sale == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
