import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/job_json.dart';
import '../../../domain/entities/job_search.dart';
import '../../bloc/jobs/jobs_search_cubit.dart';
import '../../bloc/jobs/scan/jobs_scan_bloc.dart';
import '../../bloc/jobs/scan/jobs_scan_event.dart';
import '../../bloc/jobs/scan/jobs_scan_state.dart';
import '../../widgets/jobs/jobs_ui.dart';
import 'jobs_hub_page.dart';
import 'jobs_location_picker.dart';

const _experienceLevels = {'entry': 'Entry level', 'mid': 'Mid level', 'senior': 'Senior', 'lead': 'Lead / principal', 'executive': 'Executive'};
const _employmentTypes = {'full_time': 'Full time', 'part_time': 'Part time', 'contract': 'Contract', 'temporary': 'Temporary', 'internship': 'Internship', 'freelance': 'Freelance', 'permanent': 'Permanent'};
const _arrangements = {'remote': 'Remote', 'hybrid': 'Hybrid', 'onsite': 'On-site'};
const _postedWithin = {1: 'Last 24 hours', 3: 'Last 3 days', 7: 'Last week', 14: 'Last 2 weeks', 30: 'Last 30 days', 90: 'Last 90 days'};
const _timezones = ['UTC', 'Asia/Qatar', 'Asia/Dubai', 'Asia/Riyadh', 'Asia/Karachi', 'Asia/Kolkata', 'Europe/London', 'Europe/Berlin', 'America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles', 'America/Toronto', 'Australia/Sydney'];

/// **B. Job search configuration** — countries, states, cities, titles,
/// keywords, filters and sources, with the number of searches shown before anything runs.
class JobsSearchTab extends StatelessWidget {
  const JobsSearchTab({super.key});

  @override
  Widget build(BuildContext context) {
    return JobsMessageListener<JobsSearchCubit, JobsSearchState>(
      read: (s) => s.message,
      isError: (s) => s.messageIsError,
      clear: (c) => c.clearMessage(),
      child: BlocBuilder<JobsSearchCubit, JobsSearchState>(
        builder: (context, state) {
          if (state.loading && state.countries.isEmpty) return const Center(child: CircularProgressIndicator());
          return LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 980;
            final form = _Form(state: state);
            final summary = _Summary(state: state);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 12, 40), children: [form])),
                  SizedBox(width: 340, child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(8, 12, 20, 40), child: summary)),
                ],
              );
            }
            return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 40), children: [summary, const SizedBox(height: 16), form]);
          });
        },
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.state});

  final JobsSearchState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobsSearchCubit>();
    final d = state.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SavedSearches(state: state),
        const SizedBox(height: 16),
        JobsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const JobsSectionTitle('Name', icon: AppIcons.tag),
              const SizedBox(height: 12),
              _NameField(key: ValueKey(d.id ?? 'new'), initial: d.name, onChanged: cubit.setName),
            ],
          ),
        ),
        const SizedBox(height: 16),
        JobsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const JobsSectionTitle('Where', subtitle: 'Country → state / province → city', icon: AppIcons.mapPinned),
              const SizedBox(height: 14),
              JobsLocationPicker(state: state),
            ],
          ),
        ),
        const SizedBox(height: 16),
        JobsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const JobsSectionTitle('What', subtitle: 'Every title is searched in every place', icon: AppIcons.briefcase),
              const SizedBox(height: 14),
              JobsChipInput(label: 'Job titles', hint: 'Flutter Developer — press Enter to add', values: d.titles, onAdd: cubit.addTitle, onRemove: cubit.removeTitle),
              const SizedBox(height: 18),
              JobsChipInput(label: 'Keywords (optional)', hint: 'dart, firebase — each must appear in the posting', values: d.keywords, maxItems: 12, onAdd: cubit.addKeyword, onRemove: cubit.removeKeyword),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _FiltersCard(filters: d.filters, onChanged: cubit.setFilters),
        const SizedBox(height: 16),
        _SourcesCard(state: state),
        const SizedBox(height: 16),
        _AdvancedCard(draft: d),
      ],
    );
  }
}

class _NameField extends StatefulWidget {
  const _NameField({super.key, required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: _c, maxLength: 80, decoration: const InputDecoration(labelText: 'Search name', hintText: 'e.g. Flutter jobs in California', counterText: ''), onChanged: widget.onChanged);
}

class _SavedSearches extends StatelessWidget {
  const _SavedSearches({required this.state});

  final JobsSearchState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobsSearchCubit>();
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobsSectionTitle('Saved searches', icon: AppIcons.history, trailing: TextButton.icon(onPressed: cubit.newSearch, icon: const Icon(AppIcons.plus, size: 15), label: const Text('New search'))),
          const SizedBox(height: 12),
          if (state.saved.isEmpty)
            Text('Nothing saved yet. Fill in the form below and save it to run it again later or on a daily schedule.', style: Theme.of(context).textTheme.bodySmall)
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in state.saved)
                InputChip(
                  selected: s.id == state.draft.id,
                  selectedColor: AppTheme.primary100,
                  avatar: s.schedule.enabled ? Icon(AppIcons.clock, size: 14, color: AppTheme.primary700) : null,
                  label: Text(s.name),
                  onPressed: () => cubit.edit(s),
                  onDeleted: () => _confirmDelete(context, s),
                  deleteIcon: const Icon(AppIcons.trash, size: 15),
                ),
            ]),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, JobSearch s) async {
    final cubit = context.read<JobsSearchCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this search?'),
        content: Text('"${s.name}" and its schedule will be removed. Jobs it already found are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (ok == true && s.id != null) cubit.delete(s.id!);
  }
}

class _FiltersCard extends StatelessWidget {
  const _FiltersCard({required this.filters, required this.onChanged});

  final JobSearchFilters filters;
  final ValueChanged<JobSearchFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const JobsSectionTitle('Filters', subtitle: 'Applied to what sources return. A job that doesn\'t state a value is kept.', icon: AppIcons.sliders),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final half = (c.maxWidth - 12) / 2;
            Widget field(Widget w) => SizedBox(width: c.maxWidth < 520 ? c.maxWidth : half, child: w);
            return Wrap(spacing: 12, runSpacing: 14, children: [
              field(JobsDropdown<String>(label: 'Experience level', value: filters.experienceLevel, items: _experienceLevels, onChanged: (v) => onChanged(filters.copyWith(experienceLevel: v)))),
              field(JobsDropdown<String>(label: 'Employment type', value: filters.employmentType, items: _employmentTypes, onChanged: (v) => onChanged(filters.copyWith(employmentType: v)))),
              field(JobsDropdown<String>(label: 'Work arrangement', value: filters.workArrangement, items: _arrangements, onChanged: (v) => onChanged(filters.copyWith(workArrangement: v)))),
              field(JobsDropdown<int>(label: 'Date posted', value: filters.postedWithinDays, items: _postedWithin, anyLabel: 'Any time', onChanged: (v) => onChanged(filters.copyWith(postedWithinDays: v)))),
              field(_NumberField(label: 'Minimum yearly salary', value: filters.salaryMin, onChanged: (v) => onChanged(filters.copyWith(salaryMin: v)))),
              field(TextFormField(
                initialValue: filters.salaryCurrency ?? '',
                decoration: const InputDecoration(labelText: 'Salary currency', hintText: 'USD, QAR, EUR…'),
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [LengthLimitingTextInputFormatter(3), FilteringTextInputFormatter.allow(RegExp('[A-Za-z]'))],
                onChanged: (v) => onChanged(filters.copyWith(salaryCurrency: v.length == 3 ? v.toUpperCase() : null)),
              )),
            ]);
          }),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.value, required this.onChanged});

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: value?.toString() ?? '',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
        decoration: InputDecoration(labelText: label),
        onChanged: (v) => onChanged(int.tryParse(v)),
      );
}

class _SourcesCard extends StatelessWidget {
  const _SourcesCard({required this.state});

  final JobsSearchState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobsSearchCubit>();
    final nav = JobsNavigation.of(context);
    final chosen = state.draft.sources;
    return JobsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JobsSectionTitle(
            'Sources',
            subtitle: chosen.isEmpty ? 'All enabled sources' : '${chosen.length} selected',
            icon: AppIcons.layers,
            trailing: Wrap(children: [
              if (chosen.isNotEmpty) TextButton(onPressed: cubit.useAllSources, child: const Text('Use all')),
              TextButton(onPressed: () => nav.goTo(JobsTab.sources), child: const Text('Manage')),
            ]),
          ),
          const SizedBox(height: 12),
          if (state.sources.isEmpty) Text('Sources load with the page.', style: Theme.of(context).textTheme.bodySmall),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in state.sources)
              Tooltip(
                message: !s.configured ? (s.configurationHint ?? 'Not configured') : (s.enabled ? s.description : 'Disabled in Sources'),
                child: FilterChip(
                  label: Text(s.name),
                  avatar: Icon(s.configured && s.enabled ? AppIcons.circleCheck : AppIcons.triangleAlert, size: 15, color: s.configured && s.enabled ? AppTheme.success600 : AppTheme.primary600),
                  selected: chosen.contains(s.id) || (chosen.isEmpty && s.configured && s.enabled),
                  showCheckmark: false,
                  selectedColor: s.configured && s.enabled ? AppTheme.success100 : AppTheme.primary100,
                  onSelected: (_) => cubit.toggleSource(s.id),
                ),
              ),
          ]),
          if (state.sources.any((s) => !s.configured))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Sources marked with a warning need setup (an API key or company boards) and are skipped until then.', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _AdvancedCard extends StatelessWidget {
  const _AdvancedCard({required this.draft});

  final JobSearch draft;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobsSearchCubit>();
    final l = draft.limits;
    final s = draft.schedule;
    return JobsCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: const JobsSectionTitle('Limits and schedule', subtitle: 'Control cost and when the search runs by itself', icon: AppIcons.settings),
        childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth < 520 ? c.maxWidth : (c.maxWidth - 12) / 2;
            return Wrap(spacing: 12, runSpacing: 14, children: [
              SizedBox(width: w, child: _NumberField(label: 'Most searches per scan', value: l.maxCombinations, onChanged: (v) => cubit.setLimits(l.copyWith(maxCombinations: v ?? l.maxCombinations)))),
              SizedBox(width: w, child: _NumberField(label: 'Most jobs per search', value: l.maxResultsPerCombination, onChanged: (v) => cubit.setLimits(l.copyWith(maxResultsPerCombination: v ?? l.maxResultsPerCombination)))),
              SizedBox(width: w, child: _NumberField(label: 'Result pages per source', value: l.maxPagesPerSource, onChanged: (v) => cubit.setLimits(l.copyWith(maxPagesPerSource: v ?? l.maxPagesPerSource)))),
              SizedBox(width: w, child: _NumberField(label: 'Searches at once (1–8)', value: l.concurrency, onChanged: (v) => cubit.setLimits(l.copyWith(concurrency: v ?? l.concurrency)))),
            ]);
          }),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.enabled,
            activeThumbColor: AppTheme.primary500,
            title: const Text('Run every day', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('The server starts this search by itself, once a day, even when nobody has the page open.'),
            onChanged: (v) => cubit.setSchedule(s.copyWith(enabled: v)),
          ),
          if (s.enabled)
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                icon: const Icon(AppIcons.clock, size: 16),
                label: Text('At ${s.timeOfDay}'),
                onPressed: () async {
                  final parts = s.timeOfDay.split(':');
                  final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 3, minute: int.tryParse(parts[1]) ?? 0));
                  if (picked != null) cubit.setSchedule(s.copyWith(timeOfDay: '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'));
                },
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  initialValue: _timezones.contains(s.timezone) ? s.timezone : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Time zone'),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  items: [for (final z in _timezones) DropdownMenuItem(value: z, child: Text(z))],
                  onChanged: (v) => v == null ? null : cubit.setSchedule(s.copyWith(timezone: v)),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final JobsSearchState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobsSearchCubit>();
    final e = state.estimate;
    final d = state.draft;
    final over = e != null && !e.withinLimit;
    final noSource = e != null && e.usableSources.isEmpty;
    final canRun = d.isValid && !state.saving && !over && !noSource;
    return JobsCard(
      border: over ? AppTheme.primary400 : AppTheme.primary200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.id == null ? 'New search' : 'Editing search', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(d.name.trim().isEmpty ? 'Untitled' : d.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
          const Divider(height: 28),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e == null ? '—' : thousands(e.combinations), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: over ? AppTheme.error : AppTheme.textPrimary, height: 1)),
                    const SizedBox(height: 4),
                    Text('searches per scan', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (state.estimating) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          if (e != null) ...[
            const SizedBox(height: 8),
            Text('${thousands(e.locations)} place${e.locations == 1 ? '' : 's'} × ${thousands(e.titles)} title${e.titles == 1 ? '' : 's'}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
          ] else
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Add a country and a job title to see how many searches this makes.', style: Theme.of(context).textTheme.bodySmall)),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('That is more than the limit of ${thousands(e.maxCombinations)}. Narrow the places or raise "Most searches per scan" under Limits.', style: TextStyle(fontSize: 13, color: AppTheme.error, fontWeight: FontWeight.w600)),
            ),
          if (e != null) ...[
            const SizedBox(height: 14),
            Text(
              noSource
                  ? 'No selected source is ready — set one up under Sources.'
                  : 'Will use: ${e.usableSources.map(sourceLabel).join(', ')}',
              style: TextStyle(fontSize: 12.5, color: noSource ? AppTheme.error : AppTheme.textSecondary, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 20),
          BlocBuilder<JobsScanBloc, JobsScanState>(
            builder: (context, scan) => FilledButton.icon(
              onPressed: canRun && !scan.starting
                  ? () async {
                      final nav = JobsNavigation.of(context);
                      final scanBloc = context.read<JobsScanBloc>();
                      final stored = await cubit.save();
                      if (stored?.id == null) return;
                      scanBloc.add(JobsScanBegin(stored!.id!));
                      nav.goTo(JobsTab.scans);
                    }
                  : null,
              icon: scan.starting ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary)) : const Icon(AppIcons.play, size: 16),
              label: const Text('Save and start scan'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: d.isValid && !state.saving ? () => cubit.save() : null,
            icon: state.saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.check, size: 16),
            label: Text(d.id == null ? 'Save search' : 'Save changes'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
          if (!d.isValid)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Needs a name, a country and a job title.', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
