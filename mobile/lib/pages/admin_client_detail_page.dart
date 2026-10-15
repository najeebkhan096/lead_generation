import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import '../utils/admin_analytics.dart';
import '../utils/date_format.dart';
import '../widgets/admin_sale_section.dart';
import '../widgets/admin_widgets.dart';
import 'admin_client_form.dart';
import 'admin_sale_form.dart';

/// One client business: how many orders are ongoing or done, who handled
/// them, and what was billed and collected.
class AdminClientDetailPage extends StatelessWidget {
  const AdminClientDetailPage({super.key, required this.clientName});

  final String clientName;

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    final key = clientName.trim().toLowerCase();
    final client = data.snapshot.clients.where((c) => c.name.toLowerCase() == key).firstOrNull;
    if (client == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: AppIcons.searchX, title: 'Client not found', message: 'No orders remain for this business.'),
      );
    }
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final r = client.rollup;
    final last = formatDate(client.lastActivity);

    final record = client.record;

    Future<void> openMaps() async {
      final uri = Uri.tryParse(client.mapsUrl ?? '');
      final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) showAdminMessage(context, 'Could not open the link');
    }

    Future<void> remove() async {
      final ok = await confirmAdminAction(
        context,
        title: 'Remove this client?',
        message: '${client.name} will be removed from the client list. Its orders are not deleted.',
        confirmLabel: 'Remove',
        destructive: true,
      );
      if (!ok || !context.mounted) return;
      try {
        await AdminScope.read(context).removeClient(record!.id);
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (context.mounted) showAdminError(context, e);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Client'),
        actions: [
          if (record != null) ...[
            IconButton(tooltip: 'Edit', icon: const Icon(AppIcons.edit), onPressed: () => showClientForm(context, client: record)),
            IconButton(tooltip: 'Remove', icon: Icon(AppIcons.trash, color: t.danger), onPressed: remove),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => showAdminSaleForm(context, presetBusiness: client.name),
        icon: const Icon(AppIcons.plus),
        label: const Text('New order'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
        children: [
          Row(
            children: [
              const IconHolder(icon: AppIcons.store, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.name, style: text.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        StatusPill(label: client.isActive ? 'Active' : 'All delivered', tone: client.isActive ? Tone.accent : Tone.success),
                        if (last != null) StatusPill(label: 'Last activity $last'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (client.mapsUrl != null)
            AdminCard(
              onTap: openMaps,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const IconHolder(icon: AppIcons.mapPin, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Open in Google Maps', style: text.titleSmall),
                        Text(client.mapsUrl!, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(AppIcons.externalLink, size: 18, color: t.faint),
                ],
              ),
            )
          else
            AdminCard(
              onTap: record != null ? () => showClientForm(context, client: record) : () => showClientForm(context, presetName: client.name),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const IconHolder(icon: AppIcons.mapPin, tone: Tone.danger, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No Google Maps link yet', style: text.titleSmall),
                        Text('Tap to add the business link', style: text.bodySmall),
                      ],
                    ),
                  ),
                  Icon(AppIcons.chevronRight, size: 18, color: t.faint),
                ],
              ),
            ),
          const SizedBox(height: 20),
          KpiGrid(tiles: [
            KpiTile(label: 'Ongoing', value: '${r.ongoing}', icon: AppIcons.clock, tone: Tone.accent, caption: '${r.removal} in removal · ${r.awaitingPayment} to pay'),
            KpiTile(label: 'Completed', value: '${r.completed}', icon: AppIcons.circleCheck, tone: Tone.success, caption: '${r.total} orders in total'),
            KpiTile(label: 'Billed', value: formatUsd(r.billedUsd), icon: AppIcons.banknote, tone: Tone.accent, caption: 'Excludes cancelled'),
            KpiTile(label: 'Received', value: formatPkr(r.receivedPkr), icon: AppIcons.wallet, tone: Tone.success, caption: 'Profit ${formatPkr(r.profitPkr)}'),
          ]),
          if (client.salesmen.isNotEmpty) ...[
            const SectionHeader(title: 'Handled by'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final name in client.salesmen) StatusPill(label: name, icon: AppIcons.user)],
            ),
          ],
          SectionHeader(title: 'Orders (${r.total})'),
          if (r.total == 0)
            const AdminCard(child: Center(child: Text('No orders yet. Add one with the button below.')))
          else
            AdminSaleSection(sales: r.sales, showClient: false),
          if (r.cancelled > 0) ...[
            const SizedBox(height: 4),
            Text('${r.cancelled} cancelled ${r.cancelled == 1 ? 'order is' : 'orders are'} not counted in billing totals.', style: text.bodySmall?.copyWith(color: t.faint)),
          ],
        ],
      ),
    );
  }
}
