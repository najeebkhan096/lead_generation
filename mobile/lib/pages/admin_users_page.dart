import 'package:flutter/material.dart';

import '../models/sales_user.dart';
import '../services/admin_data.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/search_field.dart';
import 'admin_salesman_detail_page.dart';

/// All accounts: who is waiting for approval, who has access, who is an
/// admin. Approve inline; tap a row for role changes and their sales.
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _search = TextEditingController();
  String _query = '';
  String? _busyId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _approve(AdminData data, SalesUser user) async {
    setState(() => _busyId = user.id);
    try {
      await data.setApproved(user, true);
      if (mounted) showAdminMessage(context, '${user.name} approved');
    } catch (e) {
      if (mounted) showAdminError(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    final q = _query.trim().toLowerCase();
    final matching = data.snapshot.users.where((u) => q.isEmpty || u.name.toLowerCase().contains(q) || (u.email ?? '').toLowerCase().contains(q)).toList();
    final pending = matching.where((u) => !u.approved).toList();
    final active = matching.where((u) => u.approved).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Users & access')),
      body: !data.loadedOnce
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: data.load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  SearchField(controller: _search, value: _query, hintText: 'Search by name or email', onChanged: (v) => setState(() => _query = v)),
                  if (pending.isNotEmpty) ...[
                    SectionHeader(title: 'Awaiting approval (${pending.length})'),
                    for (final u in pending) ...[_row(context, data, u), const SizedBox(height: 10)],
                  ],
                  SectionHeader(title: 'Active accounts (${active.length})'),
                  if (active.isEmpty)
                    const EmptyState(icon: AppIcons.users, title: 'No accounts', message: 'Nobody matches your search.')
                  else
                    for (final u in active) ...[_row(context, data, u), const SizedBox(height: 10)],
                ],
              ),
            ),
    );
  }

  Widget _row(BuildContext context, AdminData data, SalesUser user) {
    final text = Theme.of(context).textTheme;
    final busy = _busyId == user.id;
    return AdminCard(
      onTap: () => pushAdminPage(context, AdminSalesmanDetailPage(userId: user.id)),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          PersonAvatar(name: user.name, photoUrl: user.photoURL),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (user.email != null) Text(user.email!, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                StatusPill(label: user.role == 'admin' ? 'Admin' : 'Salesman', tone: user.role == 'admin' ? Tone.accent : Tone.neutral),
              ],
            ),
          ),
          if (!user.approved)
            FilledButton(
              onPressed: busy ? null : () => _approve(data, user),
              child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Approve'),
            ),
        ],
      ),
    );
  }
}
