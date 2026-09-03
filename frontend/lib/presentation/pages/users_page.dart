import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/sales_user.dart';
import '../../domain/repositories/lead_repository.dart';

/// Approve or revoke mobile app accounts. Unapproved users can sign in
/// but see no lead data — the phone shows a generic error, not this flag.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<SalesUser> _users = [];
  bool _loading = true;
  String? _error;
  String? _busyId;

  LeadRepository get _repo => context.read<LeadRepository>();

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
      final users = await _repo.listUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
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

  Future<void> _setApproved(SalesUser user, bool approved) async {
    setState(() => _busyId = user.id);
    try {
      final updated = await _repo.setUserApproved(user.id, approved: approved);
      if (!mounted) return;
      setState(() {
        _users = _users.map((u) => u.id == updated.id ? updated : u).toList();
        _busyId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _users.where((u) => !u.approved).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(AppIcons.refresh, size: 18),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _load,
                                icon: const Icon(AppIcons.refresh, size: 18),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        children: [
                          Text(
                            pending == 0
                                ? '${_users.length} user${_users.length == 1 ? '' : 's'} · all approved'
                                : '${_users.length} user${_users.length == 1 ? '' : 's'} · $pending waiting for approval',
                            style: const TextStyle(fontSize: 12.5, color: AppTheme.faint, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Approved users can see mobile lead data. Everyone else can sign in but gets a generic error — they are not told approval is required.',
                            style: TextStyle(fontSize: 12.5, color: AppTheme.faint),
                          ),
                          const SizedBox(height: 16),
                          if (_users.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text('No mobile users yet. They appear after someone signs into the app.', style: TextStyle(color: AppTheme.faint)),
                              ),
                            )
                          else
                            for (final user in _users)
                              _UserCard(
                                user: user,
                                busy: _busyId == user.id,
                                onApprove: () => _setApproved(user, true),
                                onRevoke: () => _setApproved(user, false),
                              ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.busy,
    required this.onApprove,
    required this.onRevoke,
  });

  final SalesUser user;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: user.approved ? AppTheme.sage100 : AppTheme.neutral200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.accent100,
            backgroundImage: (user.photoURL != null && user.photoURL!.isNotEmpty) ? NetworkImage(user.photoURL!) : null,
            child: (user.photoURL == null || user.photoURL!.isEmpty)
                ? Text(
                    user.name.trim().isEmpty ? '?' : user.name.trim()[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.accent700),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user.email != null && user.email!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    user.email!,
                    style: const TextStyle(fontSize: 12, color: AppTheme.faint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  user.approved ? 'Approved · can see mobile data' : 'Not approved',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: user.approved ? AppTheme.sage700 : AppTheme.accent700,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          else if (user.approved)
            TextButton(onPressed: onRevoke, child: const Text('Revoke'))
          else
            FilledButton(onPressed: onApprove, child: const Text('Approve')),
        ],
      ),
    );
  }
}
