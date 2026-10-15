import 'package:flutter/material.dart';

import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import '../utils/admin_analytics.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/page_header.dart';
import '../widgets/search_field.dart';
import 'admin_salesman_detail_page.dart';

/// Every salesman with live counts of ongoing and completed sales and what
/// they are owed. Tap one for their full page.
class AdminSalesmenPage extends StatefulWidget {
  const AdminSalesmenPage({super.key});

  @override
  State<AdminSalesmenPage> createState() => _AdminSalesmenPageState();
}

class _AdminSalesmenPageState extends State<AdminSalesmenPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(title: 'Salesmen', subtitle: 'Performance, ongoing and completed sales'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SearchField(
              controller: _search,
              value: _query,
              hintText: 'Search salesmen',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: AdminLoadGate(builder: (context, data) => _list(context, data)),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, AdminData data) {
    final q = _query.trim().toLowerCase();
    final all = data.snapshot.salesmen;
    final matching = all.where((s) => q.isEmpty || s.user.name.toLowerCase().contains(q) || (s.user.email ?? '').toLowerCase().contains(q));
    // Accounts awaiting a decision go first; the rest keep busiest-first order.
    final shown = [
      ...matching.where((s) => !s.user.approved),
      ...matching.where((s) => s.user.approved),
    ];

    if (shown.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            icon: all.isEmpty ? AppIcons.users : AppIcons.searchX,
            title: all.isEmpty ? 'No salesmen yet' : 'No matches',
            message: all.isEmpty ? 'Accounts appear here after they sign up in the app.' : 'Try a different name or email.',
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _SalesmanCard(summary: shown[i]),
    );
  }
}

class _SalesmanCard extends StatelessWidget {
  const _SalesmanCard({required this.summary});

  final SalesmanSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final user = summary.user;
    final r = summary.rollup;
    return AdminCard(
      onTap: () => pushAdminPage(context, AdminSalesmanDetailPage(userId: user.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(name: user.name, photoUrl: user.photoURL),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (user.email != null) Text(user.email!, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (!user.approved) const StatusPill(label: 'Pending', tone: Tone.danger) else Icon(AppIcons.chevronRight, size: 18, color: t.faint),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(label: 'Ongoing', value: '${r.ongoing}', color: r.ongoing > 0 ? t.accentText : null),
              _Stat(label: 'Completed', value: '${r.completed}', color: r.completed > 0 ? t.sageText : null),
              _Stat(label: 'Due', value: formatPkr(r.payablePkr), color: r.payablePkr > 0 ? t.accentText : null, flex: 2),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color, this.flex = 1});

  final String label;
  final String value;
  final Color? color;
  final int flex;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
