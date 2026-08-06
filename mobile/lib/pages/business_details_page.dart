import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';

class BusinessDetailsPage extends StatefulWidget {
  const BusinessDetailsPage({super.key, required this.lead});

  final Lead lead;

  @override
  State<BusinessDetailsPage> createState() => _BusinessDetailsPageState();
}

class _BusinessDetailsPageState extends State<BusinessDetailsPage> {
  final _repo = LeadRepository();
  late LeadStatus _currentStatus;
  late bool _hasWhatsApp;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.lead.status;
    _hasWhatsApp = widget.lead.hasWhatsApp;
  }

  Future<void> _saveChanges() async {
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      if (_currentStatus != widget.lead.status) {
        await _repo.updateStatus(widget.lead.id, _currentStatus, user?.uid);
      }
      if (_hasWhatsApp != widget.lead.hasWhatsApp) {
        await _repo.updateWhatsAppStatus(widget.lead.id, _hasWhatsApp, user?.uid);
      }
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

  Future<void> _openReviews() async {
    final ok = await openGoogleMaps(widget.lead.mapsUrl);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google reviews')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lead = widget.lead;
    final dirty = _currentStatus != lead.status || _hasWhatsApp != lead.hasWhatsApp;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
          children: [
            _Hero(lead: lead),
            if (lead.mapsUrl != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _openReviews,
                icon: Icon(AppIcons.externalLink, size: 18, color: t.accentText),
                label: const Text('Read the reviews on Google'),
              ),
            ],
            const SizedBox(height: 28),
            _ReviewCard(review: lead.badReview),
            const SizedBox(height: 32),
            Text('WhatsApp Validation',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            _WhatsAppToggle(
              value: _hasWhatsApp,
              onChanged: (val) => setState(() => _hasWhatsApp = val),
            ),
            const SizedBox(height: 32),
            Text('Where does this lead stand?',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            for (final option in _statusOptions)
              _StatusOption(
                option: option,
                selected: _currentStatus == option.status,
                onTap: () => setState(() => _currentStatus = option.status),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: !dirty || _loading ? null : _saveChanges,
              icon: _loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: t.onFill),
                    )
                  : const Icon(AppIcons.check, size: 20),
              label: Text(dirty ? 'Save changes' : 'Data up to date'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhatsAppToggle extends StatelessWidget {
  const _WhatsAppToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(
          'WhatsApp Validated',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: value ? t.sageTextStrong : t.ink,
          ),
        ),
        subtitle: Text(
          value
              ? 'This number is confirmed on WhatsApp'
              : 'Status not yet validated',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        secondary: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: value ? t.sageTint : t.neutralTint,
            shape: BoxShape.circle,
          ),
          child: Icon(
            AppIcons.chat,
            size: 20,
            color: value ? t.sage : t.subtle,
          ),
        ),
        activeColor: t.sage,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: t.accentTint,
            borderRadius:
                const BorderRadius.all(Radius.circular(AppTheme.radiusPill)),
          ),
          child: Text(
            lead.category,
            style: TextStyle(
              color: t.accentTextStrong,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(lead.business, style: Theme.of(context).textTheme.displaySmall),
        if (lead.rating != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(AppIcons.star, size: 18, color: t.accent),
              const SizedBox(width: 6),
              Text(
                lead.rating!.toStringAsFixed(1),
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: t.ink, fontSize: 16),
              ),
              if (lead.totalReviews != null) ...[
                const SizedBox(width: 6),
                Text(
                  '· ${lead.totalReviews} reviews on Google',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// The sales hook: the worst recent review, quoted in full — or a sage
/// "clean reputation" note when none was captured.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final BadReview review;

  bool get _hasReview => review.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasReview) return const _CleanReputationCard();
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.all(24),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.accentTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.quote, size: 20, color: t.accentText),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('The review that stings',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    _Stars(count: review.stars),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '“${review.text.trim()}”',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: t.ink,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(AppIcons.user, size: 15, color: t.faint),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  review.reviewer ?? 'Anonymous reviewer',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              Icon(AppIcons.clock, size: 15, color: t.faint),
              const SizedBox(width: 6),
              Text(review.date, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _CleanReputationCard extends StatelessWidget {
  const _CleanReputationCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: t.sageTint,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.sageTintStrong,
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.shieldCheck, size: 20, color: t.sageText),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No bad review captured',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: t.sageTextStrong)),
                const SizedBox(height: 4),
                Text(
                  'Their reputation looks clean right now.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: t.sageText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        for (var i = 0; i < 5; i++) ...[
          Icon(
            AppIcons.star,
            size: 15,
            color: i < count ? t.accent : t.border,
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
  }
}

class _StatusOptionData {
  const _StatusOptionData(this.status, this.label, this.hint, this.icon);

  final LeadStatus status;
  final String label;
  final String hint;
  final IconData icon;
}

const _statusOptions = [
  _StatusOptionData(LeadStatus.lead, 'New Lead', 'Not approached yet', AppIcons.compass),
  _StatusOptionData(LeadStatus.contacted, 'Contacted', 'First message sent', AppIcons.send),
  _StatusOptionData(LeadStatus.booked, 'Order Placed', 'They put in an order', AppIcons.packageCheck),
  _StatusOptionData(LeadStatus.dealDone, 'Deal Done', 'Signed and won', AppIcons.circleCheck),
];

class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _StatusOptionData option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Deal Done celebrates in sage; everything else speaks terracotta.
    final isWin = option.status == LeadStatus.dealDone;
    final tint = isWin ? t.sageTint : t.accentTint;
    final deep = isWin ? t.sageText : t.accentText;
    final fill = isWin ? t.sage : t.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? tint : t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radius + 4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? fill : t.neutralTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    option.icon,
                    size: 20,
                    color: selected ? t.onFill : t.subtle,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: selected ? deep : t.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(option.hint,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (selected)
                  Icon(AppIcons.circleCheck, size: 22, color: deep),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
