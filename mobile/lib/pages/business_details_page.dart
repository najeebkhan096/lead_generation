import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';

class BusinessDetailsPage extends StatefulWidget {
  const BusinessDetailsPage({super.key, required this.lead});

  final Lead lead;

  @override
  State<BusinessDetailsPage> createState() => _BusinessDetailsPageState();
}

class _BusinessDetailsPageState extends State<BusinessDetailsPage> {
  final _repo = LeadRepository();
  final _reputationController = TextEditingController();
  late LeadStatus _currentStatus;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _reputationController.text = widget.lead.reputationStatus;
    _currentStatus = widget.lead.status;
  }

  @override
  void dispose() {
    _reputationController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _loading = true);
    try {
      await _repo.updateStatus(widget.lead.id, _currentStatus);
      await _repo.updateReputationStatus(widget.lead.id, _reputationController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Changes saved')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save changes')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _launch(
    BuildContext context,
    Future<bool> Function() action,
    String failureMessage,
  ) async {
    final ok = await action();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final addedOn = formatDate(widget.lead.dateAdded);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Details'),
        actions: [
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(strokeWidth: 2)))
          else
            TextButton(
              onPressed: _saveChanges,
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          _buildInfoCard(context, addedOn),
          const SizedBox(height: 24),
          Text('Action & Status', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _buildStatusPicker(),
          const SizedBox(height: 16),
          _buildReputationField(),
          const SizedBox(height: 24),
          if (widget.lead.badReview.text.trim().isNotEmpty) ...[
            Text('Critical Review', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildReviewCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String? addedOn) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.lead.business,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 24),
                ),
              ),
              if (widget.lead.rating != null) _RatingBadge(rating: widget.lead.rating!),
            ],
          ),
          const SizedBox(height: 8),
          _DetailRow(icon: Icons.category_outlined, label: 'Category', value: widget.lead.category),
          _DetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: widget.lead.phone,
            onTap: widget.lead.phone == null ? null : () => _launch(context, () => openPhone(widget.lead.phone), 'Error'),
          ),
          _DetailRow(
            icon: Icons.public_outlined,
            label: 'Website',
            value: widget.lead.website,
            onTap: widget.lead.website == null ? null : () => _launch(context, () => openWebsite(widget.lead.website), 'Error'),
          ),
          _DetailRow(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: widget.lead.address,
            onTap: widget.lead.mapsUrl == null ? null : () => _launch(context, () => openGoogleMaps(widget.lead.mapsUrl), 'Error'),
          ),
          _DetailRow(icon: Icons.event_note_outlined, label: 'Date Found', value: addedOn),
        ],
      ),
    );
  }

  Widget _buildStatusPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LeadStatus>(
          value: _currentStatus,
          isExpanded: true,
          items: LeadStatus.values.map((status) {
            return DropdownMenuItem(
              value: status,
              child: Text(status.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _currentStatus = val);
          },
        ),
      ),
    );
  }

  Widget _buildReputationField() {
    return TextFormField(
      controller: _reputationController,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: 'Reputation Management Progress',
        hintText: 'e.g. Sent response, review removed, awaiting customer reply...',
        alignLabelWithHint: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.black.withOpacity(0.1))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.black.withOpacity(0.1))),
      ),
    );
  }

  Widget _buildReviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: AppTheme.warn, size: 18),
              const SizedBox(width: 4),
              Text(
                '${widget.lead.badReview.stars}★ · ${widget.lead.badReview.date}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.warn),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(widget.lead.badReview.text, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  final double rating;
  const _RatingBadge({required this.rating});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 16, color: AppTheme.warn),
          const SizedBox(width: 4),
          Text(rating.toStringAsFixed(1), style: const TextStyle(color: AppTheme.warn, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value, this.onTap});
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.slate.withOpacity(0.5)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasValue ? value! : 'N/A',
                style: TextStyle(
                  color: onTap != null ? AppTheme.accent : AppTheme.ink,
                  fontWeight: onTap != null ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
