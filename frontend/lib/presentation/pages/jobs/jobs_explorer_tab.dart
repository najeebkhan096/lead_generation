import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/job.dart';
import '../../../domain/entities/job_filters.dart';
import '../../../domain/entities/job_geo.dart';
import '../../../domain/entities/job_json.dart';
import '../../../domain/entities/job_source_info.dart';
import '../../../domain/repositories/jobs_repository.dart';
import '../../bloc/jobs/explorer/jobs_explorer_bloc.dart';
import '../../bloc/jobs/explorer/jobs_explorer_event.dart';
import '../../bloc/jobs/explorer/jobs_explorer_state.dart';
import '../../bloc/jobs/jobs_errors.dart';
import '../../bloc/jobs/jobs_overview_cubit.dart';
import '../../utils/web_download.dart';
import '../../widgets/jobs/job_card.dart';
import '../../widgets/jobs/jobs_ui.dart';
import 'jobs_hub_page.dart';

const _experience = {'entry': 'Entry level', 'mid': 'Mid level', 'senior': 'Senior', 'lead': 'Lead / principal', 'executive': 'Executive'};
const _employment = {'full_time': 'Full time', 'part_time': 'Part time', 'contract': 'Contract', 'temporary': 'Temporary', 'internship': 'Internship', 'freelance': 'Freelance', 'permanent': 'Permanent'};
const _arrangement = {'remote': 'Remote', 'hybrid': 'Hybrid', 'onsite': 'On-site'};
const _posted = {1: 'Last 24 hours', 3: 'Last 3 days', 7: 'Last week', 14: 'Last 2 weeks', 30: 'Last 30 days', 90: 'Last 90 days'};

/// **D. Jobs Explorer** — the discovered jobs, filtered, sorted and paged by the
/// server; the app only ever holds the pages it has scrolled through.
class JobsExplorerTab extends StatefulWidget {
  const JobsExplorerTab({super.key});

  @override
  State<JobsExplorerTab> createState() => _JobsExplorerTabState();
}

class _JobsExplorerTabState extends State<JobsExplorerTab> {
  final _scroll = ScrollController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        context.read<JobsExplorerBloc>().add(const JobsExplorerLoadMore());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(Job job) async {
    final changed = await context.push<bool>('/jobs/${Uri.encodeComponent(job.id)}');
    if (changed == true && mounted) context.read<JobsExplorerBloc>().add(const JobsExplorerRefreshed());
  }

  Future<void> _triage(Job job, JobTriage action) async {
    final bloc = context.read<JobsExplorerBloc>();
    if (action == JobTriage.delete) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this job?'),
          content: Text('"${job.title}" at ${job.companyName} is removed, and later scans will not bring it back.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppTheme.error))),
          ],
        ),
      );
      if (ok != true) return;
    }
    bloc.add(JobsExplorerTriaged(job.id, action));
  }

  Future<void> _export({required bool selected}) async {
    final bloc = context.read<JobsExplorerBloc>();
    final repo = context.read<JobsRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = selected ? await repo.exportSelectedJobs(bloc.state.selected.toList()) : await repo.exportJobs(bloc.state.filters);
      downloadBytesFile('jobs-${DateTime.now().toIso8601String().substring(0, 10)}.csv', bytes, 'text/csv');
      messenger.showSnackBar(SnackBar(content: Text(selected ? 'Exported ${bloc.state.selected.length} selected jobs.' : 'Exported every job that matches the filters.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(jobsErrorMessage(e))));
    }
  }

  Future<void> _saveAlert() async {
    final filters = context.read<JobsExplorerBloc>().state.filters;
    final overview = context.read<JobsOverviewCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(context: context, builder: (ctx) => const _NameDialog(title: 'Save as alert', hint: 'e.g. Remote Flutter roles', body: 'After each scan, new jobs matching these filters are counted on the Overview.'));
    if (name == null || name.trim().length < 2) return;
    await overview.createAlert(name.trim(), {
      'q': filters.query,
      'countryCode': filters.countryCode,
      'state': filters.state,
      'city': filters.city,
      'workArrangement': filters.workArrangement,
      'employmentType': filters.employmentType,
      'experienceLevel': filters.experienceLevel,
      'salaryMin': filters.salaryMin,
      'skills': filters.skills,
      'source': filters.source,
    }..removeWhere((k, v) => v == null || (v is List && v.isEmpty)));
    messenger.showSnackBar(const SnackBar(content: Text('Alert saved. See it on the Overview.')));
  }

  @override
  Widget build(BuildContext context) {
    return JobsMessageListener<JobsExplorerBloc, JobsExplorerState>(
      read: (s) => s.message,
      isError: (s) => s.messageIsError,
      clear: (b) => b.add(const JobsExplorerMessageCleared()),
      child: BlocBuilder<JobsExplorerBloc, JobsExplorerState>(
        builder: (context, state) {
          final bloc = context.read<JobsExplorerBloc>();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _Toolbar(state: state, search: _search, onFilters: () => _filters(state.filters), onExport: _export, onAlert: _saveAlert),
              ),
              if (state.hasSelection) _SelectionBar(state: state, onExport: () => _export(selected: true)),
              Expanded(child: _body(context, state, bloc)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, JobsExplorerState state, JobsExplorerBloc bloc) {
    if (state.loading && state.jobs.isEmpty) return const Center(child: CircularProgressIndicator());
    if (state.status == JobsExplorerStatus.failure && state.jobs.isEmpty) {
      return Padding(padding: const EdgeInsets.all(20), child: JobsErrorBanner(state.error ?? 'Could not load jobs.', onRetry: () => bloc.add(const JobsExplorerRefreshed())));
    }
    if (state.jobs.isEmpty) {
      final filtered = state.filters.hasExtraFilters;
      return JobsEmpty(
        icon: filtered ? AppIcons.searchX : AppIcons.briefcase,
        title: filtered ? 'No jobs match these filters' : (state.filters.view == JobView.active || state.filters.view == JobView.all ? 'No jobs found yet' : 'Nothing in "${state.filters.view.label}"'),
        body: filtered ? 'Loosen a filter, or clear them all.' : 'Run a scan from the Search tab and the jobs it finds will appear here.',
        action: filtered
            ? OutlinedButton(onPressed: () => bloc.add(JobsExplorerFiltersChanged(state.filters.cleared())), child: const Text('Clear filters'))
            : FilledButton(onPressed: () => JobsNavigation.of(context).goTo(JobsTab.search), child: const Text('Set up a search')),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => bloc.add(const JobsExplorerRefreshed()),
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        itemCount: state.jobs.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == state.jobs.length) {
            if (state.loadingMore) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            if (state.hasMore) return Center(child: TextButton(onPressed: () => bloc.add(const JobsExplorerLoadMore()), child: const Text('Load more')));
            return Padding(padding: const EdgeInsets.all(16), child: Center(child: Text('That\'s everything · ${thousands(state.jobs.length)} job${state.jobs.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.bodySmall)));
          }
          final job = state.jobs[i];
          return JobCard(
            key: ValueKey(job.id),
            job: job,
            selected: state.selected.contains(job.id),
            busy: state.busy.contains(job.id),
            onToggleSelect: () => bloc.add(JobsExplorerToggled(job.id)),
            onOpen: () => _open(job),
            onTriage: (a) => _triage(job, a),
          );
        },
      ),
    );
  }

  Future<void> _filters(JobFilters current) async {
    final bloc = context.read<JobsExplorerBloc>();
    final result = await showDialog<JobFilters>(context: context, builder: (ctx) => _FiltersDialog(initial: current, repo: context.read<JobsRepository>()));
    if (result != null) bloc.add(JobsExplorerFiltersChanged(result));
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.state, required this.search, required this.onFilters, required this.onExport, required this.onAlert});

  final JobsExplorerState state;
  final TextEditingController search;
  final VoidCallback onFilters;
  final Future<void> Function({required bool selected}) onExport;
  final VoidCallback onAlert;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<JobsExplorerBloc>();
    final f = state.filters;
    final extra = [f.countryCode, f.state, f.city, f.company, f.experienceLevel, f.employmentType, f.workArrangement, f.source, f.runId].where((v) => v != null).length +
        (f.skills.isEmpty ? 0 : 1) +
        (f.salaryMin == null ? 0 : 1) +
        (f.postedWithinDays == null ? 0 : 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final v in JobView.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: JobChoicePill(label: v.label, selected: f.view == v, onTap: () => bloc.add(JobsExplorerFiltersChanged(f.copyWith(view: v)))),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 340,
              child: TextField(
                controller: search,
                decoration: InputDecoration(
                  hintText: 'Search title, company, skill or place',
                  prefixIcon: const Icon(AppIcons.search, size: 18),
                  isDense: true,
                  suffixIcon: search.text.isEmpty ? null : IconButton(icon: const Icon(AppIcons.close, size: 16), onPressed: () { search.clear(); bloc.add(const JobsExplorerQueryChanged('')); }),
                ),
                onChanged: (v) => bloc.add(JobsExplorerQueryChanged(v)),
              ),
            ),
            OutlinedButton.icon(onPressed: onFilters, icon: const Icon(AppIcons.sliders, size: 16), label: Text(extra == 0 ? 'Filters' : 'Filters · $extra')),
            if (f.hasExtraFilters) TextButton(onPressed: () { search.clear(); bloc.add(JobsExplorerFiltersChanged(f.cleared())); }, child: const Text('Clear')),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<JobSort>(
                initialValue: f.sort,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sort', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                borderRadius: BorderRadius.circular(AppTheme.radius),
                items: [for (final s in JobSort.values) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: (s) => s == null ? null : bloc.add(JobsExplorerFiltersChanged(f.copyWith(sort: s))),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Export and alerts',
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radius)),
              onSelected: (v) => v == 'csv' ? onExport(selected: false) : onAlert(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'csv', child: Text('Export all matches (CSV)')),
                PopupMenuItem(value: 'alert', child: Text('Save these filters as an alert')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(border: Border.all(color: AppTheme.neutral300, width: 1.5), borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(AppIcons.download, size: 16), SizedBox(width: 8), Text('Export', style: TextStyle(fontWeight: FontWeight.w700)), SizedBox(width: 4), Icon(AppIcons.chevronDown, size: 14)]),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            state.loading ? 'Loading…' : (state.total != null ? '${thousands(state.total!)} job${state.total == 1 ? '' : 's'}' : '${thousands(state.jobs.length)} loaded${state.hasMore ? ' · more below' : ''}'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.state, required this.onExport});

  final JobsExplorerState state;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<JobsExplorerBloc>();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: AppTheme.primary100, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text('${state.selected.length} selected', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary800)),
          TextButton(onPressed: state.allLoadedSelected ? null : () => bloc.add(const JobsExplorerSelectLoaded()), child: const Text('Select all loaded')),
          TextButton(onPressed: () => bloc.add(const JobsExplorerSelectionCleared()), child: const Text('Clear')),
          FilledButton.icon(onPressed: onExport, icon: const Icon(AppIcons.download, size: 15), label: const Text('Export selected'), style: FilledButton.styleFrom(minimumSize: const Size(0, 38))),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.hint, required this.body});

  final String title;
  final String hint;
  final String body;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.body),
          const SizedBox(height: 14),
          TextField(controller: _c, autofocus: true, maxLength: 80, decoration: InputDecoration(hintText: widget.hint), onSubmitted: (v) => Navigator.pop(context, v)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
        ],
      );
}

class _FiltersDialog extends StatefulWidget {
  const _FiltersDialog({required this.initial, required this.repo});

  final JobFilters initial;
  final JobsRepository repo;

  @override
  State<_FiltersDialog> createState() => _FiltersDialogState();
}

class _FiltersDialogState extends State<_FiltersDialog> {
  late JobFilters _f = widget.initial;
  late final _city = TextEditingController(text: widget.initial.city ?? '');
  late final _company = TextEditingController(text: widget.initial.company ?? '');
  late final _skills = TextEditingController(text: widget.initial.skills.join(', '));
  late final _salary = TextEditingController(text: widget.initial.salaryMin?.toString() ?? '');
  late final _currency = TextEditingController(text: widget.initial.salaryCurrency ?? '');
  List<JobCountry> _countries = const [];
  List<JobRegion> _regions = const [];
  List<JobSourceInfo> _sources = const [];

  @override
  void initState() {
    super.initState();
    widget.repo.countries().then((c) => mounted ? setState(() => _countries = c) : null).catchError((_) {});
    widget.repo.sources().then((s) => mounted ? setState(() => _sources = s) : null).catchError((_) {});
    if (_f.countryCode != null) _loadRegions(_f.countryCode!);
  }

  @override
  void dispose() {
    for (final c in [_city, _company, _skills, _salary, _currency]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRegions(String code) async {
    try {
      final r = await widget.repo.regions(code);
      if (mounted) setState(() => _regions = r);
    } catch (_) {}
  }

  JobFilters _collect() {
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return _f.copyWith(
      city: t(_city),
      company: t(_company),
      skills: _skills.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      salaryMin: int.tryParse(_salary.text.trim()),
      salaryCurrency: _currency.text.trim().length == 3 ? _currency.text.trim().toUpperCase() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final countryItems = {for (final c in _countries.where((c) => !c.remoteOnly)) c.code: c.name};
    final regionItems = {for (final r in _regions) r.name: r.name};
    return AlertDialog(
      title: const Text('Filter jobs'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [
              _half(JobsDropdown<String>(label: 'Country', value: _f.countryCode, items: countryItems, onChanged: (v) {
                setState(() {
                  _f = _f.copyWith(countryCode: v, state: null);
                  _regions = const [];
                });
                if (v != null) _loadRegions(v);
              })),
              _half(JobsDropdown<String>(label: 'State / province', value: _f.state, items: regionItems, onChanged: (v) => setState(() => _f = _f.copyWith(state: v)))),
              _half(TextField(controller: _city, decoration: const InputDecoration(labelText: 'City'))),
              _half(TextField(controller: _company, decoration: const InputDecoration(labelText: 'Company'))),
              SizedBox(width: 548, child: TextField(controller: _skills, decoration: const InputDecoration(labelText: 'Skills (all required)', hintText: 'Flutter, Dart, Firebase'))),
              _half(JobsDropdown<String>(label: 'Experience', value: _f.experienceLevel, items: _experience, onChanged: (v) => setState(() => _f = _f.copyWith(experienceLevel: v)))),
              _half(JobsDropdown<String>(label: 'Employment type', value: _f.employmentType, items: _employment, onChanged: (v) => setState(() => _f = _f.copyWith(employmentType: v)))),
              _half(JobsDropdown<String>(label: 'Remote / hybrid / on-site', value: _f.workArrangement, items: _arrangement, onChanged: (v) => setState(() => _f = _f.copyWith(workArrangement: v)))),
              _half(JobsDropdown<String>(label: 'Source', value: _f.source, items: {for (final s in _sources) s.id: s.name}, onChanged: (v) => setState(() => _f = _f.copyWith(source: v)))),
              _half(TextField(controller: _salary, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Salary at least (yearly)'))),
              _half(TextField(controller: _currency, textCapitalization: TextCapitalization.characters, maxLength: 3, decoration: const InputDecoration(labelText: 'Currency', counterText: '', hintText: 'USD'))),
              _half(JobsDropdown<int>(label: 'Date posted', value: _f.postedWithinDays, items: _posted, anyLabel: 'Any time', onChanged: (v) => setState(() => _f = _f.copyWith(postedWithinDays: v)))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, widget.initial.cleared()), child: const Text('Clear all')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _collect()), child: const Text('Apply')),
      ],
    );
  }

  Widget _half(Widget child) => SizedBox(width: 268, child: child);
}
