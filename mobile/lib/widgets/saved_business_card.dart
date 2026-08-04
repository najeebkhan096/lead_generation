import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    final user = FirebaseAuth.instance.currentUser;
    try {
      await _repo.updateStatus(widget.lead.id, status, user?.uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to ${status.label}')),
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
    final t = context.tokens;
    final addedOn = formatDate(widget.lead.dateAdded);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _InitialAvatar(name: widget.lead.business),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.lead.business,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.lead.category,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: t.accentText,
                                    fontWeight: FontWeight.w700,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: AppIcons.heart,
                        background: _isFavorite ? t.accentTint : t.neutralTint,
                        foreground: _isFavorite ? t.accentDeep : t.faint,
                        onTap: _toggleFavorite,
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
                      Icon(AppIcons.mapPin, size: 15, color: t.faint),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          widget.lead.location,
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (addedOn != null) ...[
                        const SizedBox(width: 8),
                        Text(addedOn,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatusBadge(status: widget.lead.status),
                      ),
                      const SizedBox(width: 12),
                      _WhatsAppButton(
                        onTap: () => openWhatsApp(widget.lead.whatsAppUrl),
                      ),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: AppIcons.more,
                        background: t.neutralTint,
                        foreground: t.subtle,
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
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: context.tokens.border,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
              ),
              const SizedBox(height: 20),
              Text('Update lead status',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              _buildStatusOption(context, LeadStatus.lead, 'New Lead', AppIcons.compass),
              _buildStatusOption(context, LeadStatus.contacted, 'Contacted', AppIcons.send),
              _buildStatusOption(context, LeadStatus.booked, 'Order Placed', AppIcons.packageCheck),
              _buildStatusOption(context, LeadStatus.dealDone, 'Deal Done', AppIcons.circleCheck),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOption(BuildContext context, LeadStatus status, String label, IconData icon) {
    final t = context.tokens;
    final isSelected = widget.lead.status == status;
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isSelected ? t.accentTint : t.neutralTint,
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 20, color: isSelected ? t.accentTextStrong : t.subtle),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
          color: isSelected ? t.accentTextStrong : t.ink,
        ),
      ),
      trailing: isSelected
          ? Icon(AppIcons.check, size: 20, color: t.accentDeep)
          : null,
      onTap: () {
        Navigator.pop(context);
        _updateStatus(status);
      },
    );
  }
}

/// Circle with the business's first letter in the display face. Tint
/// alternates between the two accent voices so lists feel hand-arranged.
class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final warm = name.hashCode.isEven;
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: warm ? t.accentTint : t.sageTint,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: GoogleFonts.caprasimo(
          fontSize: 21,
          color: warm ? t.accentText : t.sageText,
        ),
      ),
    );
  }
}

class _RatingInfo extends StatelessWidget {
  final double rating;
  const _RatingInfo({required this.rating});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.star, size: 16, color: t.accent),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(fontWeight: FontWeight.w700, color: t.ink),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final LeadStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (label, background, foreground) = switch (status) {
      // Terracotta = outreach emphasis; sage = positive momentum and wins.
      LeadStatus.lead => ('NEW LEAD', t.neutralTint, t.subtle),
      LeadStatus.contacted => ('CONTACTED', t.accentTint, t.accentTextStrong),
      LeadStatus.booked => ('ORDER PLACED', t.sageTint, t.sageTextStrong),
      LeadStatus.dealDone => ('DEAL DONE', t.sage, t.onFill),
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

/// Sage = the "online / reach them now" voice.
class _WhatsAppButton extends StatelessWidget {
  final VoidCallback onTap;
  const _WhatsAppButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.sage,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        splashColor: t.sageDeep,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.chat, color: t.onFill, size: 17),
              const SizedBox(width: 8),
              Text(
                'WhatsApp',
                style: TextStyle(
                  color: t.onFill,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: foreground, size: 19),
        ),
      ),
    );
  }
}
