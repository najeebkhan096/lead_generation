import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/lead_repository.dart';
import '../widgets/saved_business_card.dart';

const _allCategories = 'All categories';

/// Which lead signal a verified lead came from.
enum _Source { all, review, website }

/// Every business whose phone number a real WhatsApp check confirmed — the
/// `whatsappLeads` collection. Validating a review lead or a no-website
/// lead (from Leads, or from an Excel Archive) copies it here; this is the
/// list to work from, separate from the leads it came from.
class WhatsAppLeadsPage extends StatefulWidget {
  const WhatsAppLeadsPage({super.key});

  @override
  State<WhatsAppLeadsPage> createState() => _WhatsAppLeadsPageState();
}

class _WhatsAppLeadsPageState extends State<WhatsAppLeadsPage> {
  final _search = TextEditingController();
  List<Lead> _leads = [];
  bool _loading = true;
  String? _error;
  String _category = _allCategories;
  _Source _source = _Source.all;
  String? _deletingId;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final leads = await _repo.getWhatsAppLeads();
      if (!mounted) return;
      setState(() {
        _leads = leads;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _open(Lead lead) async {
    final url = (lead.waLink?.isNotEmpty ?? false)
        ? lead.waLink
        : 'https://wa.me/${(lead.phone ?? '').replaceAll(RegExp(r'\D'), '')}';
    final uri = Uri.tryParse(url ?? '');
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
  }

  Future<void> _delete(Lead lead) async {
    if (lead.dbId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from WhatsApp leads?'),
        content: Text(
          '"${lead.business}" is removed from this list. The original lead it was '
          'validated from is not touched.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _deletingId = lead.dbId);
    try {
      await _repo.deleteWhatsAppLead(lead.dbId!);
      if (!mounted) return;
      setState(() => _leads = _leads.where((l) => l.dbId != lead.dbId).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  List<String> get _categories {
    final present = <String>{for (final l in _leads) if (l.category.trim().isNotEmpty) l.category.trim()};
    return [_allCategories, ...(present.toList()..sort())];
  }

  List<Lead> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _leads.where((l) {
      if (_category != _allCategories && l.category != _category) return false;
      if (_source == _Source.review && l.sourceType != 'review') return false;
      if (_source == _Source.website && l.sourceType != 'website') return false;
      if (q.isEmpty) return true;
      return l.business.toLowerCase().contains(q) ||
          (l.phone?.toLowerCase().contains(q) ?? false) ||
          (l.address?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final effectiveCategory = categories.contains(_category) ? _category : _allCategories;
    final visible = _visible;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
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
                                    Text('WhatsApp leads', style: Theme.of(context).textTheme.displaySmall),
                                    const SizedBox(height: 6),
                                    Text(
                                      _leads.isEmpty
                                          ? 'Businesses with a confirmed WhatsApp number will land here.'
                                          : '${_leads.length} business${_leads.length == 1 ? '' : 'es'} '
                                              'with a confirmed WhatsApp number.',
                                      style: Theme.of(context).textTheme.bodyLarge,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Refresh',
                                onPressed: _load,
                                icon: const Icon(AppIcons.refresh),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.surface,
                                  padding: const EdgeInsets.all(12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          if (_loading && _leads.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 100),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_error != null)
                            _Message(
                              icon: AppIcons.alert,
                              title: 'Could not load WhatsApp leads',
                              body: _error!,
                              action: OutlinedButton.icon(
                                onPressed: _load,
                                icon: const Icon(AppIcons.refresh, size: 18),
                                label: const Text('Retry'),
                              ),
                            )
                          else if (_leads.isEmpty)
                            const _Message(
                              icon: AppIcons.chat,
                              title: 'No WhatsApp leads yet',
                              body: 'Open Leads (or an Excel Archive) and tap WhatsApp to check numbers — '
                                  'the ones that are on WhatsApp are saved here.',
                            )
                          else ...[
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 320,
                                  child: TextField(
                                    controller: _search,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      hintText: 'Search by name, phone, or address',
                                      prefixIcon: Icon(AppIcons.search, size: 19),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 260,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: effectiveCategory,
                                    isExpanded: true,
                                    icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
                                    decoration: const InputDecoration(prefixIcon: Icon(AppIcons.filter, size: 19)),
                                    items: [
                                      for (final c in categories)
                                        DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
                                    ],
                                    onChanged: (v) => setState(() => _category = v ?? _allCategories),
                                  ),
                                ),
                                SegmentedButton<_Source>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(value: _Source.all, label: Text('All')),
                                    ButtonSegment(value: _Source.review, label: Text('1-star')),
                                    ButtonSegment(value: _Source.website, label: Text('No website')),
                                  ],
                                  selected: {_source},
                                  onSelectionChanged: (s) => setState(() => _source = s.first),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (visible.isEmpty)
                              const _Message(
                                icon: AppIcons.searchX,
                                title: 'No matches',
                                body: 'Try a different name, phone number, or filter.',
                              )
                            else
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: visible.length,
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 340,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  mainAxisExtent: 248,
                                ),
                                itemBuilder: (context, i) {
                                  final lead = visible[i];
                                  return SavedBusinessCard(
                                    lead: lead,
                                    onTap: () => _open(lead),
                                    onDelete: lead.dbId == null ? null : () => _delete(lead),
                                    deleting: _deletingId != null && _deletingId == lead.dbId,
                                  );
                                },
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppTheme.accent700),
          ),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(body, style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}
