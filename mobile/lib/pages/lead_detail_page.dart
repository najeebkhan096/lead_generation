import 'package:flutter/material.dart';

import '../features/twilio_outreach/services/outreach_api.dart';
import '../features/twilio_outreach/twilio_outreach_page.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';

/// Everything known about one verified business, with the action to start a
/// WhatsApp conversation — which opens the in-app Outreach chat (Twilio), not
/// the WhatsApp app.
class LeadDetailPage extends StatefulWidget {
  const LeadDetailPage({super.key, required this.row, required this.category, required this.onMessage});

  final Map<String, dynamic> row;
  final String category;

  /// Claims the lead for this salesman. Return false to stop (taken / error).
  final Future<bool> Function() onMessage;

  @override
  State<LeadDetailPage> createState() => _LeadDetailPageState();
}

class _LeadDetailPageState extends State<LeadDetailPage> {
  bool _opening = false;

  String _v(String key) => (widget.row[key] ?? '').toString().trim();

  Future<void> _message() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      if (!await widget.onMessage()) return;
      if (!mounted) return;
      final name = _v('Business Name');
      await openOutreachChat(
        context,
        name: name,
        businessName: name,
        phoneNumber: _v('Phone'),
        details: {
          if (widget.category.isNotEmpty) 'Category': widget.category,
          if (_v('Rating').isNotEmpty) 'Rating': _v('Rating'),
          for (final e in widget.row.entries)
            if (!const {'Business Name', 'Phone', 'Rating', 'Category'}.contains(e.key) && e.value.toString().trim().isNotEmpty)
              e.key: e.value.toString().trim(),
        },
      );
    } on OutreachApiException catch (e) {
      _snack(e.code == 'INVALID_PHONE' ? 'This phone number is not a valid WhatsApp number.' : e.message);
    } catch (e) {
      _snack('Could not open the chat: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = _v('Business Name');
    final phone = _v('Phone');
    final rating = _v('Rating');
    final mapsUrl = _v('Maps URL');
    const shown = {'Business Name', 'Phone', 'Rating', 'Maps URL'};
    final extra = [
      for (final e in widget.row.entries)
        if (!shown.contains(e.key) && e.value.toString().trim().isNotEmpty) MapEntry(e.key, e.value.toString().trim()),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Lead details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(name.isEmpty ? 'Unnamed business' : name, style: Theme.of(context).textTheme.headlineSmall),
          if (widget.category.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(widget.category, style: TextStyle(color: t.faint, fontWeight: FontWeight.w600)),
          ],
          if (rating.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              Icon(AppIcons.star, size: 16, color: t.accentText),
              const SizedBox(width: 4),
              Text(rating, style: TextStyle(fontWeight: FontWeight.w700, color: t.accentText)),
            ]),
          ],
          const SizedBox(height: 20),
          if (phone.isNotEmpty) _Field(label: 'Phone', value: phone, icon: AppIcons.phone, onTap: () => openPhone(phone)),
          for (final e in extra) _Field(label: e.key, value: e.value),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: phone.isEmpty || _opening ? null : _message,
            style: FilledButton.styleFrom(
              backgroundColor: t.sage,
              foregroundColor: t.onFill,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _opening
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(AppIcons.chat, size: 18),
            label: const Text('WhatsApp'),
          ),
          if (mapsUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => openGoogleMaps(mapsUrl),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(AppIcons.mapPin, size: 18),
              label: const Text('Review'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.icon, this.onTap});

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: t.subtle), const SizedBox(width: 8)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: t.faint, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14.5)),
            ]),
          ),
        ]),
      ),
    );
  }
}
