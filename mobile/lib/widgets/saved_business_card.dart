import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';

class SavedBusinessCard extends StatefulWidget {
  const SavedBusinessCard({super.key, required this.lead, required this.onTap});

  final Lead lead;
  final VoidCallback onTap;

  @override
  State<SavedBusinessCard> createState() => _SavedBusinessCardState();
}

class _SavedBusinessCardState extends State<SavedBusinessCard> {
  late bool _isFavorite;
  final _repo = LeadRepository();

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.lead.isFavorite;
  }

  Future<void> _toggleFavorite() async {
    setState(() => _isFavorite = !_isFavorite);
    try {
      await _repo.updateFavorite(widget.lead.id, _isFavorite);
    } catch (e) {
      if (mounted) {
        setState(() => _isFavorite = !_isFavorite);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update favorite')),
        );
      }
    }
  }

  Future<void> _updateStatus(LeadStatus status) async {
    try {
      await _repo.updateStatus(widget.lead.id, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to ${status.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update status')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final addedOn = formatDate(widget.lead.dateAdded);
    final statusColor = _getStatusColor(widget.lead.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.lead.business,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            _CategoryBadge(category: widget.lead.category),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleFavorite,
                        icon: Icon(
                          _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: _isFavorite ? Colors.red : AppTheme.slate.withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (widget.lead.rating != null) ...[
                        _RatingInfo(rating: widget.lead.rating!),
                        const SizedBox(width: 16),
                      ],
                      Icon(Icons.location_on_outlined, size: 16, color: AppTheme.slate.withOpacity(0.5)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.lead.location,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.slate.withOpacity(0.7)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _StatusBadge(status: widget.lead.status, color: statusColor),
                      ),
                      const SizedBox(width: 12),
                      _ActionIconButton(
                        icon: Icons.chat_rounded,
                        color: AppTheme.whatsApp,
                        onTap: () => openWhatsApp(widget.lead.whatsAppUrl),
                      ),
                      const SizedBox(width: 8),
                      _ActionIconButton(
                        icon: Icons.more_horiz_rounded,
                        color: AppTheme.accent,
                        onTap: () => _showActionSheet(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Update Lead Status', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _buildStatusOption(context, LeadStatus.lead, 'New Lead', Icons.explore_outlined),
            _buildStatusOption(context, LeadStatus.contacted, 'Contacted', Icons.send_rounded),
            _buildStatusOption(context, LeadStatus.booked, 'Meeting Booked', Icons.event_available_rounded),
            _buildStatusOption(context, LeadStatus.dealDone, 'Deal Done', Icons.check_circle_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOption(BuildContext context, LeadStatus status, String label, IconData icon) {
    final isSelected = widget.lead.status == status;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppTheme.accent : AppTheme.slate),
      title: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      trailing: isSelected ? const Icon(Icons.check, color: AppTheme.accent) : null,
      onTap: () {
        Navigator.pop(context);
        _updateStatus(status);
      },
    );
  }

  Color _getStatusColor(LeadStatus status) {
    switch (status) {
      case LeadStatus.lead: return AppTheme.slate;
      case LeadStatus.contacted: return AppTheme.accent;
      case LeadStatus.booked: return AppTheme.warn;
      case LeadStatus.dealDone: return AppTheme.success;
    }
  }
}

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        category,
        style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
      ),
    );
  }
}

class _RatingInfo extends StatelessWidget {
  final double rating;
  const _RatingInfo({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFBBF24)),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final LeadStatus status;
  final Color color;
  const _StatusBadge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    String label = status.name.toUpperCase();
    if (status == LeadStatus.dealDone) label = 'DEAL DONE';
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionIconButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}
