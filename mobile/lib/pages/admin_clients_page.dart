import 'package:flutter/material.dart';

import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import '../utils/admin_analytics.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/page_header.dart';
import '../widgets/search_field.dart';
import 'admin_client_detail_page.dart';
import 'admin_client_form.dart';

enum _ClientFilter { all, active, delivered }

/// Client businesses — every order grouped by business so the admin can see
/// which clients have work in flight and which are fully delivered.
class AdminClientsPage extends StatefulWidget {
  const AdminClientsPage({super.key});

  @override
  State<AdminClientsPage> createState() => _AdminClientsPageState();
}

class _AdminClientsPageState extends State<AdminClientsPage> {
  final _search = TextEditingController();
  String _query = '';
  _ClientFilter _filter = _ClientFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loaded = AdminScope.of(context).loadedOnce;
    return Stack(
      children: [
        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(title: 'Clients', subtitle: 'Businesses and the status of their orders'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SearchField(
                  controller: _search,
                  value: _query,
                  hintText: 'Search clients',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(child: AdminLoadGate(builder: _content)),
            ],
          ),
        ),
        Positioned(
          right: 20,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'admin-add-client',
            onPressed: loaded ? () => showClientForm(context) : null,
            icon: const Icon(AppIcons.plus),
            label: const Text('Add client'),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, AdminData data) {
    final all = data.snapshot.clients;
    final q = _query.trim().toLowerCase();
    final shown = all.where((c) {
      if (q.isNotEmpty && !c.name.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _ClientFilter.all => true,
        _ClientFilter.active => c.isActive,
        _ClientFilter.delivered => !c.isActive,
      };
    }).toList();
    final activeCount = all.where((c) => c.isActive).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final (f, label) in [
              (_ClientFilter.all, 'All ${all.length}'),
              (_ClientFilter.active, 'Active $activeCount'),
              (_ClientFilter.delivered, 'Delivered ${all.length - activeCount}'),
            ])
              _FilterPill(label: label, selected: _filter == f, onTap: () => setState(() => _filter = f)),
          ],
        ),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          EmptyState(
            icon: all.isEmpty ? AppIcons.store : AppIcons.searchX,
            title: all.isEmpty ? 'No clients yet' : 'No matches',
            message: all.isEmpty ? 'Add a client with its business name and Google Maps link.' : 'Try another name or filter.',
          )
        else
          for (final c in shown) ...[
            _ClientCard(client: c),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: t.accentTint,
      backgroundColor: t.surface,
      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: selected ? t.accentTextStrong : t.subtle),
      side: BorderSide(color: selected ? t.accent : t.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client});

  final ClientSummary client;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final r = client.rollup;
    final who = client.salesmen.isEmpty
        ? 'No salesman assigned'
        : client.salesmen.length <= 2
            ? client.salesmen.join(', ')
            : '${client.salesmen.take(2).join(', ')} +${client.salesmen.length - 2}';

    return AdminCard(
      onTap: () => pushAdminPage(context, AdminClientDetailPage(clientName: client.name)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconHolder(icon: AppIcons.store, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.name, style: text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(who, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(AppIcons.chevronRight, size: 18, color: t.faint),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (client.mapsUrl == null) const StatusPill(label: 'Add map link', tone: Tone.danger, icon: AppIcons.mapPin),
              StatusPill(label: r.total == 0 ? 'No orders yet' : '${r.total} ${r.total == 1 ? 'order' : 'orders'}'),
              if (r.ongoing > 0) StatusPill(label: '${r.ongoing} ongoing', tone: Tone.accent),
              if (r.completed > 0) StatusPill(label: '${r.completed} completed', tone: Tone.success),
              if (r.cancelled > 0) StatusPill(label: '${r.cancelled} cancelled', tone: Tone.danger),
              if (r.billedUsd > 0) StatusPill(label: 'Billed ${formatUsd(r.billedUsd)}'),
            ],
          ),
        ],
      ),
    );
  }
}
