import 'package:flutter/material.dart';

import '../models/client_record.dart';
import '../services/admin_data.dart';
import '../utils/maps_url.dart';
import '../widgets/admin_widgets.dart';

/// Add a client, or edit one. A client is only a business name and the link
/// to its Google Maps listing — both are required. Returns the saved client,
/// or null when dismissed.
Future<ClientRecord?> showClientForm(
  BuildContext context, {
  ClientRecord? client,
  String? presetName,
}) {
  final data = AdminScope.read(context);
  return showModalBottomSheet<ClientRecord>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ClientForm(data: data, client: client, presetName: presetName),
  );
}

class _ClientForm extends StatefulWidget {
  const _ClientForm({required this.data, this.client, this.presetName});

  final AdminData data;
  final ClientRecord? client;
  final String? presetName;

  @override
  State<_ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<_ClientForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.client?.name ?? widget.presetName ?? '');
  late final TextEditingController _url = TextEditingController(text: widget.client?.mapsUrl ?? '');
  bool _saving = false;

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
    final clash = widget.data.snapshot.clientRecords.any((c) => c.id != widget.client?.id && clientNameKey(c.name) == key);
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
    setState(() => _saving = true);
    try {
      final saved = widget.client == null
          ? await widget.data.addClient(name: name, mapsUrl: url)
          : await widget.data.editClient(widget.client!.id, name: name, mapsUrl: url);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAdminError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isNew = widget.client == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(isNew ? 'Add client' : 'Edit client', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text('A client is its business name and Google Maps link.', style: text.bodyMedium),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              autofocus: isNew && (widget.presetName ?? '').isEmpty,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: _validateName,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Google Maps link',
                hintText: 'https://maps.app.goo.gl/…',
                helperText: 'Open the business in Google Maps → Share → Copy link',
              ),
              validator: _validateUrl,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(isNew ? 'Add client' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
