import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/lead_card.dart';

class LeadsPage extends StatelessWidget {
  const LeadsPage({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final repo = LeadRepository();

    return Scaffold(
      appBar: AppBar(
        title: Text(category),
      ),
      body: StreamBuilder<List<Lead>>(
        stream: repo.watchLeads(category: category),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // Fallback without orderBy if composite index is missing.
            return StreamBuilder<List<Lead>>(
              stream: repo.watchLeadsFallback(category: category),
              builder: (context, fallback) {
                if (fallback.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (fallback.hasError) {
                  return _ErrorBody(message: fallback.error.toString());
                }
                return _LeadsList(leads: fallback.data ?? const []);
              },
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return _LeadsList(leads: snapshot.data ?? const []);
        },
      ),
    );
  }
}

class _LeadsList extends StatelessWidget {
  const _LeadsList({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    if (leads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.inbox_outlined, size: 48, color: AppTheme.slate),
              const SizedBox(height: 12),
              Text(
                'No businesses saved yet',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Run a nationwide search in LeadFinder and tap Save to Firebase.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: leads.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${leads.length} business${leads.length == 1 ? '' : 'es'}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.ink,
                  ),
            ),
          );
        }
        return LeadCard(lead: leads[index - 1]);
      },
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFB91C1C)),
        ),
      ),
    );
  }
}
