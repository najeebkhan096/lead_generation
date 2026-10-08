import 'package:flutter/material.dart';
import '../models/outreach_lead.dart';
import '../services/outreach_repository.dart';

/// Bottom sheet listing the user's leads; returns the chosen one.
Future<OutreachLead?> pickLead(BuildContext context, {String? excludeId}) {
  return showModalBottomSheet<OutreachLead>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scroll) => StreamBuilder<List<OutreachLead>>(
        stream: OutreachRepository().watchLeads(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final leads = snap.data!.where((l) => l.id != excludeId).toList();
          if (leads.isEmpty) return const Center(child: Text('No other leads'));
          return ListView.builder(
            controller: scroll,
            itemCount: leads.length,
            itemBuilder: (_, i) => ListTile(
              leading: CircleAvatar(child: Text(leads[i].initial)),
              title: Text(leads[i].displayName),
              subtitle: Text(leads[i].phoneNumber),
              onTap: () => Navigator.pop(ctx, leads[i]),
            ),
          );
        },
      ),
    ),
  );
}
