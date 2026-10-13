import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/sales_user.dart';
import '../../domain/entities/twilio_test_lead.dart';
import '../../domain/repositories/lead_repository.dart';

/// Adds throwaway leads for trying the Twilio outreach flow. Nothing is sent
/// from here: a test lead just appears in the chosen mobile user's Outreach
/// inbox, where messages can be sent to it. Only leads created on this page
/// can be deleted from it.
class TwilioTestLeadsPage extends StatefulWidget {
  const TwilioTestLeadsPage({super.key});

  @override
  State<TwilioTestLeadsPage> createState() => _TwilioTestLeadsPageState();
}

class _TwilioTestLeadsPageState extends State<TwilioTestLeadsPage> {
  final _name = TextEditingController();
  final _business = TextEditingController();
  final _phone = TextEditingController();
  final _form = GlobalKey<FormState>();

  List<TwilioTestLead> _leads = const [];
  List<SalesUser> _owners = const [];

  /// Empty = the backend's default test owner (no mobile inbox shows it).
  String _ownerId = '';
  bool _loading = true;
  bool _saving = false;
  String? _listError;
  String? _formError;
  String? _notice;
  String? _deletingId;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _business.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _listError = null;
    });
    try {
      final leads = await _repo.listTwilioTestLeads();
      // Owners only decide whose inbox shows the lead; the page still works
      // (with the default owner) if the user list can't be loaded.
      final owners = await _repo.listUsers().then((u) => u.where((x) => x.approved).toList()).catchError((_) => <SalesUser>[]);
      if (!mounted) return;
      setState(() {
        _leads = leads;
        _owners = owners;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listError = _message(e);
        _loading = false;
      });
    }
  }

  static String _message(Object e) => e.toString().replaceFirst('Exception: ', '');

  /// Arabic-Indic / Persian digits to ASCII and no separators, like the mobile app.
  static String _normalizePhone(String input) {
    final sb = StringBuffer();
    for (final r in input.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        sb.writeCharCode(0x30 + r - 0x0660);
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        sb.writeCharCode(0x30 + r - 0x06F0);
      } else {
        sb.writeCharCode(r);
      }
    }
    return sb.toString().replaceAll(RegExp(r'[\s\-().]'), '');
  }

  String? _validatePhone(String? v) {
    final p = _normalizePhone(v ?? '');
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(p) ? null : 'Use international format, e.g. +971501234567';
  }

  Future<void> _add() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _formError = null;
      _notice = null;
    });
    try {
      final r = await _repo.createTwilioTestLead(
        phoneNumber: _normalizePhone(_phone.text),
        name: _name.text.trim(),
        businessName: _business.text.trim(),
        ownerId: _ownerId,
      );
      final leads = await _repo.listTwilioTestLeads();
      if (!mounted) return;
      setState(() {
        _leads = leads;
        _saving = false;
        _notice = r.created
            ? 'Test lead added (${r.lead.id}).'
            : r.isTest
                ? 'That number is already a test lead for this owner — nothing changed.'
                : 'That owner already has a real lead for this number — it was left untouched.';
        if (r.created) {
          _name.clear();
          _business.clear();
          _phone.clear();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = _message(e);
      });
    }
  }

  Future<void> _delete(TwilioTestLead lead) async {
    setState(() => _deletingId = lead.id);
    try {
      await _repo.deleteTwilioTestLead(lead.id);
      if (!mounted) return;
      setState(() {
        _leads = _leads.where((l) => l.id != lead.id).toList();
        _deletingId = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  String _ownerLabel(String ownerId) {
    for (final u in _owners) {
      if (u.id == ownerId) return u.name;
    }
    return ownerId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Twilio test leads'),
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                const Text(
                  'Add a lead to try the Twilio outreach flow. Nothing is sent from here — the lead appears in the '
                  'selected mobile user\'s Outreach inbox, where you can message it.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.faint),
                ),
                const SizedBox(height: 16),
                _buildForm(),
                const SizedBox(height: 28),
                _buildList(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _phone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+971501234567',
                helperText: 'Any country. Include the + and the country code.',
              ),
              validator: _validatePhone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Contact name (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _business,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Business name (optional)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _ownerId,
              decoration: const InputDecoration(
                labelText: 'Show in the Outreach inbox of',
                helperText: 'Only approved mobile users are listed.',
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Nobody (default test owner)')),
                for (final u in _owners)
                  DropdownMenuItem(
                    value: u.id,
                    child: Text(u.email == null || u.email!.isEmpty ? u.name : '${u.name} · ${u.email}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _saving ? null : (v) => setState(() => _ownerId = v ?? ''),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Text(_formError!, style: const TextStyle(color: AppTheme.danger, fontSize: 12.5)),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 12),
              Text(_notice!, style: const TextStyle(color: AppTheme.sage700, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _add,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(AppIcons.plus, size: 18),
                label: const Text('Add test lead'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final header = Text(
      _loading || _listError != null ? 'Test leads' : 'Test leads · ${_leads.length}',
      style: const TextStyle(fontSize: 12.5, color: AppTheme.faint, fontWeight: FontWeight.w700),
    );
    if (_loading) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header,
        const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator())),
      ]);
    }
    if (_listError != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header,
        const SizedBox(height: 12),
        Text(_listError!, style: const TextStyle(color: AppTheme.danger)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: _load, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      const SizedBox(height: 10),
      if (_leads.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No test leads yet.', style: TextStyle(color: AppTheme.faint))),
        )
      else
        for (final lead in _leads)
          _TestLeadCard(
            lead: lead,
            ownerLabel: lead.ownerId.isEmpty ? '' : _ownerLabel(lead.ownerId),
            busy: _deletingId == lead.id,
            onOpen: () => context.push('/twilio-test/chat', extra: lead),
            onDelete: () => _delete(lead),
          ),
    ]);
  }
}

class _TestLeadCard extends StatelessWidget {
  const _TestLeadCard({
    required this.lead,
    required this.ownerLabel,
    required this.busy,
    required this.onOpen,
    required this.onDelete,
  });

  final TwilioTestLead lead;
  final String ownerLabel;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = lead.businessName.isNotEmpty
        ? lead.businessName
        : lead.name.isNotEmpty
            ? lead.name
            : lead.phoneNumber;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.phone, size: 18, color: AppTheme.accent700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  [lead.phoneNumber, if (ownerLabel.isNotEmpty) ownerLabel].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppTheme.faint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(AppIcons.chat, size: 16),
              label: const Text('Chat'),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(AppIcons.trash, size: 18),
              tooltip: 'Delete test lead',
            ),
          ],
        ],
      ),
    );
  }
}
