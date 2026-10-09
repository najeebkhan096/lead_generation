import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/chat_controller.dart';
import '../models/outreach_lead.dart';
import '../services/outreach_api.dart';
import '../services/outreach_repository.dart';
import '../services/template_image.dart';
import '../widgets/message_bubble.dart';
import 'chat_page.dart';

class LeadListPage extends StatefulWidget {
  const LeadListPage({super.key, this.onExit});

  /// Back button callback; null when embedded as a tab.
  final VoidCallback? onExit;

  @override
  State<LeadListPage> createState() => _LeadListPageState();
}

class _LeadListPageState extends State<LeadListPage> {
  final _repo = OutreachRepository();
  final _api = OutreachApi();
  late final Stream<List<OutreachLead>> _stream;
  bool _importing = false;
  final Set<String> _sendingTemplate = {};

  @override
  void initState() {
    super.initState();
    _stream = _repo.watchLeads();
    unawaited(_migrate());
  }

  Future<void> _migrate() async {
    try {
      final moved = await _repo.migrateLegacyLeads(_api);
      if (moved > 0) _snack('Moved $moved saved leads to the cloud.');
    } catch (e) {
      debugPrint('[Outreach] migration skipped: $e'); // retried next open
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _sendTemplate(OutreachLead lead) async {
    if (_sendingTemplate.contains(lead.id)) return;
    setState(() => _sendingTemplate.add(lead.id));
    final c = ChatController(leadId: lead.id);
    try {
      final url = await pickAndUploadTemplateImage(context, recipient: lead.displayName);
      if (url == null) return;
      c.sendTemplate(url);
      final err = await c.settle();
      _snack(err ?? 'Template sent to ${lead.displayName}');
    } catch (e) {
      _snack('Could not send template: $e');
    } finally {
      c.dispose();
      if (mounted) setState(() => _sendingTemplate.remove(lead.id));
    }
  }

  Future<void> _importFromTwilio() async {
    setState(() => _importing = true);
    try {
      final r = await _api.importFromTwilio();
      _snack(r.created == 0 ? 'No new contacts found in Twilio history.' : 'Imported ${r.created} contacts from Twilio history.');
    } on OutreachApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _addLead() async {
    final name = TextEditingController();
    final business = TextEditingController();
    final phone = TextEditingController();
    final form = GlobalKey<FormState>();
    var saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add Lead'),
          content: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Contact Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(controller: business, decoration: const InputDecoration(labelText: 'Business Name')),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number', hintText: '+971501234567'),
                validator: (v) {
                  final p = _normalizePhone(v ?? '');
                  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(p) ? null : 'Use international format, e.g. +971501234567';
                },
              ),
              if (error != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Colors.red.shade400, fontSize: 12))),
            ]),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      setLocal(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await _api.ensureLead(
                          name: name.text.trim(),
                          businessName: business.text.trim(),
                          phoneNumber: _normalizePhone(phone.text),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } on OutreachApiException catch (e) {
                        setLocal(() {
                          saving = false;
                          error = e.message;
                        });
                      }
                    },
              child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  /// Arabic-Indic / Persian digits to ASCII, strip separators (same as the old screen).
  static String _normalizePhone(String input) {
    final sb = StringBuffer();
    for (final r in input.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        sb.write(r - 0x0660);
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        sb.write(r - 0x06F0);
      } else {
        sb.writeCharCode(r);
      }
    }
    return sb.toString().replaceAll(RegExp(r'[\s\-().]'), '');
  }

  Future<void> _rename(OutreachLead lead) async {
    final name = TextEditingController(text: lead.name);
    final business = TextEditingController(text: lead.businessName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit lead'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Contact Name')),
          TextField(controller: business, decoration: const InputDecoration(labelText: 'Business Name')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      try {
        await _repo.renameLead(lead.id, name: name.text.trim(), businessName: business.text.trim());
      } catch (e) {
        _snack('Could not save: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onExit == null ? null : BackButton(onPressed: widget.onExit),
        automaticallyImplyLeading: widget.onExit != null,
        title: const Text('WhatsApp Business Outreach'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'import') _importFromTwilio();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Import contacts from Twilio history')),
            ],
          ),
          if (_importing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addLead,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Lead'),
      ),
      body: StreamBuilder<List<OutreachLead>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off, size: 40),
                  const SizedBox(height: 8),
                  const Text("Couldn't load your leads."),
                  Text('${snap.error}', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                ]),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final leads = snap.data!;
          if (leads.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.people_outline, size: 56),
                const SizedBox(height: 12),
                const Text('No leads added yet'),
                const SizedBox(height: 12),
                FilledButton(onPressed: _addLead, child: const Text('Add Your First Lead')),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: leads.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) => _LeadTile(
              lead: leads[i],
              sendingTemplate: _sendingTemplate.contains(leads[i].id),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(lead: leads[i]))),
              onLongPress: () => _rename(leads[i]),
              onTemplate: () => _sendTemplate(leads[i]),
            ),
          );
        },
      ),
    );
  }
}

class _LeadTile extends StatelessWidget {
  const _LeadTile({
    required this.lead,
    required this.sendingTemplate,
    required this.onTap,
    required this.onLongPress,
    required this.onTemplate,
  });

  final OutreachLead lead;
  final bool sendingTemplate;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onTemplate;

  @override
  Widget build(BuildContext context) {
    final unread = lead.unreadCount > 0;
    final sub = [if (lead.name.isNotEmpty && lead.name != lead.displayName && lead.name != lead.phoneNumber) lead.name, lead.phoneNumber].join(' • ');
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: lead.profileImage != null ? NetworkImage(lead.profileImage!) : null,
        child: lead.profileImage == null ? Text(lead.initial) : null,
      ),
      title: Row(children: [
        Expanded(child: Text(lead.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600))),
        if (lead.lastMessageAt != null)
          Text(_listTime(lead.lastMessageAt!), style: TextStyle(fontSize: 11, color: unread ? const Color(0xFF128C7E) : null)),
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        Row(children: [
          Expanded(
            child: Text(lead.lastMessage.isEmpty ? 'No messages yet' : lead.lastMessage,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w600 : null)),
          ),
          if (unread)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF25D366), borderRadius: BorderRadius.circular(10)),
              child: Text('${lead.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
        ]),
      ]),
      trailing: sendingTemplate
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(onPressed: onTemplate, child: const Text('Template')),
    );
  }

  static String _listTime(DateTime t) {
    final label = dayLabel(t);
    return label == 'Today' ? clockTime(t) : label;
  }
}
