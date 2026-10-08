import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/outreach_lead.dart';

/// Contact card opened by tapping the chat header: business, phone and any
/// details saved from the lead (category, address, rating, ...).
class LeadInfoPage extends StatelessWidget {
  const LeadInfoPage({super.key, required this.lead});
  final OutreachLead lead;

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      if (lead.businessName.isNotEmpty) MapEntry('Business', lead.businessName),
      if (lead.name.isNotEmpty && lead.name != lead.businessName && lead.name != lead.phoneNumber)
        MapEntry('Contact', lead.name),
      MapEntry('Phone', lead.phoneNumber),
      ...lead.details.entries,
      MapEntry('Added', _date(lead.createdAt)),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Contact info')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundImage: lead.profileImage != null ? NetworkImage(lead.profileImage!) : null,
            child: lead.profileImage == null ? Text(lead.initial, style: const TextStyle(fontSize: 30)) : null,
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text(lead.displayName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height: 16),
        for (final r in rows)
          ListTile(
            title: Text(r.key, style: const TextStyle(fontSize: 12)),
            subtitle: Text(r.value, style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: r.value));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r.key} copied')));
            },
          ),
      ]),
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
