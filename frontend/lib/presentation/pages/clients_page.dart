import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/maps_url.dart';
import '../../domain/entities/client_record.dart';
import '../../domain/repositories/lead_repository.dart';

/// The client list: each client is just a business name and the link to its
/// Google Maps listing. Both are required when adding one.
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _search = TextEditingController();
  List<ClientRecord> _clients = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clients = await _repo.listClients();
      if (!mounted) return;
      setState(() {
        _clients = clients;
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

  Future<void> _edit({ClientRecord? client}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ClientDialog(client: client, existing: _clients),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(ClientRecord client) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this client?'),
        content: Text('${client.name} will be removed from the client list. Its sales are not deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteClient(client.id);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _open(ClientRecord client) async {
    final uri = Uri.tryParse(client.mapsUrl ?? '');
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = _clients.where((c) => q.isEmpty || c.name.toLowerCase().contains(q)).toList();
    final missing = _clients.where((c) => !c.hasMapsUrl).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clients'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(AppIcons.refresh, size: 18),
            tooltip: 'Refresh',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _loading ? null : () => _edit(),
              icon: const Icon(AppIcons.plus, size: 18),
              label: const Text('Add client'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
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
                            missing == 0
                                ? '${_clients.length} client${_clients.length == 1 ? '' : 's'}'
                                : '${_clients.length} client${_clients.length == 1 ? '' : 's'} · $missing without a Google Maps link',
                            style: const TextStyle(fontSize: 12.5, color: AppTheme.faint, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _search,
                            onChanged: (v) => setState(() => _query = v),
                            decoration: const InputDecoration(
                              hintText: 'Search clients',
                              prefixIcon: Icon(AppIcons.search, size: 18),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (shown.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 48),
                              child: Center(
                                child: Text(
                                  _clients.isEmpty
                                      ? 'No clients yet. Add one with its business name and Google Maps link.'
                                      : 'No clients match your search.',
                                  style: const TextStyle(color: AppTheme.faint),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else
                            for (final c in shown) ...[
                              _ClientRow(
                                client: c,
                                onOpen: () => _open(c),
                                onEdit: () => _edit(client: c),
                                onDelete: () => _delete(c),
                              ),
                              const SizedBox(height: 10),
                            ],
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client, required this.onOpen, required this.onEdit, required this.onDelete});

  final ClientRecord client;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppTheme.accent100, borderRadius: BorderRadius.circular(12)),
            child: const Icon(AppIcons.store, size: 19, color: AppTheme.accent700),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(client.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                client.hasMapsUrl
                    ? Text(
                        client.mapsUrl!,
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.faint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const Text(
                        'No Google Maps link yet',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.danger, fontWeight: FontWeight.w600),
                      ),
              ],
            ),
          ),
          if (client.hasMapsUrl)
            IconButton(onPressed: onOpen, icon: const Icon(AppIcons.externalLink, size: 18), tooltip: 'Open in Google Maps'),
          IconButton(onPressed: onEdit, icon: const Icon(AppIcons.edit, size: 18), tooltip: 'Edit'),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(AppIcons.trash, size: 18, color: AppTheme.danger),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

class _ClientDialog extends StatefulWidget {
  const _ClientDialog({this.client, required this.existing});

  final ClientRecord? client;
  final List<ClientRecord> existing;

  @override
  State<_ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends State<_ClientDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.client?.name ?? '');
  late final _url = TextEditingController(text: widget.client?.mapsUrl ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    final name = (v ?? '').trim();
    if (name.isEmpty) return 'Enter the business name';
    final key = clientNameKey(name);
    final clash = widget.existing.any((c) => c.id != widget.client?.id && clientNameKey(c.name) == key);
    return clash ? 'This business is already a client' : null;
  }

  String? _validateUrl(String? v) {
    if ((v ?? '').trim().isEmpty) return 'Paste the Google Maps link';
    return normalizeMapsUrl(v) == null ? 'That is not a Google Maps link' : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final url = normalizeMapsUrl(_url.text)!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = context.read<LeadRepository>();
      if (widget.client == null) {
        await repo.createClient(name: name, mapsUrl: url);
      } else {
        await repo.updateClient(widget.client!.id, name: name, mapsUrl: url);
      }
      if (mounted) Navigator.pop(context, true);
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
      title: Text(widget.client == null ? 'Add client' : 'Edit client'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Business name'),
                validator: _validateName,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _url,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Google Maps link',
                  hintText: 'https://maps.app.goo.gl/...',
                  helperText: 'Open the business in Google Maps, Share, Copy link',
                ),
                validator: _validateUrl,
                onFieldSubmitted: (_) => _save(),
              ),
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface))
              : Text(widget.client == null ? 'Add client' : 'Save'),
        ),
      ],
    );
  }
}
