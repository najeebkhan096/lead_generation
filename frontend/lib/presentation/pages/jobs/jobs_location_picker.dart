import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/job_geo.dart';
import '../../../domain/entities/job_json.dart';
import '../../../domain/entities/job_search.dart';
import '../../bloc/jobs/jobs_search_cubit.dart';

/// **Where to look** — Country → State / Province → City.
///
/// Each country is searched at one depth (whole country, each state, or each
/// city). States and cities can be "all" or hand-picked; the number of
/// searches this expands to is shown in the summary as it changes.
class JobsLocationPicker extends StatelessWidget {
  const JobsLocationPicker({super.key, required this.state});

  final JobsSearchState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobsSearchCubit>();
    final chosen = state.draft.countries.map((c) => c.code).toSet();
    final available = state.countries.where((c) => !chosen.contains(c.code)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<JobCountry>(
                key: ValueKey(chosen.length),
                isExpanded: true,
                initialValue: null,
                decoration: const InputDecoration(labelText: 'Add a country', hintText: 'Choose…'),
                borderRadius: BorderRadius.circular(AppTheme.radius),
                items: [
                  for (final c in available)
                    DropdownMenuItem(
                      value: c,
                      child: Text(c.remoteOnly ? '${c.name} (remote jobs anywhere)' : '${c.name}  ·  ${thousands(c.regionCount)} ${c.regionNoun.toLowerCase()}s, ${thousands(c.cityCount)} cities'),
                    ),
                ],
                onChanged: available.isEmpty ? null : (c) => c == null ? null : cubit.addCountry(c),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (state.draft.countries.isEmpty) Text('Pick at least one country. Add several to search them together.', style: Theme.of(context).textTheme.bodySmall),
        for (final sel in state.draft.countries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _CountryCard(selection: sel, state: state),
          ),
      ],
    );
  }
}

class _CountryCard extends StatelessWidget {
  const _CountryCard({required this.selection, required this.state});

  final JobCountrySelection selection;
  final JobsSearchState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobsSearchCubit>();
    final country = state.country(selection.code);
    final noun = (country?.regionNoun ?? 'Region');
    final regions = state.regions[selection.code];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radius), border: Border.all(color: AppTheme.neutral200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(selection.isWorldwide ? AppIcons.globe : AppIcons.mapPinned, size: 18, color: AppTheme.primary700),
              const SizedBox(width: 10),
              Expanded(child: Text(selection.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 16))),
              IconButton(tooltip: 'Remove ${selection.name}', icon: const Icon(AppIcons.close, size: 18), onPressed: () => cubit.removeCountry(selection.code)),
            ],
          ),
          if (selection.isWorldwide)
            Text('Remote jobs that are open to people anywhere. No state or city to choose.', style: Theme.of(context).textTheme.bodySmall)
          else ...[
            const SizedBox(height: 8),
            SegmentedButton<JobSearchLevel>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: JobSearchLevel.country, label: Text('Whole country')),
                ButtonSegment(value: JobSearchLevel.state, label: Text('Each ${noun.toLowerCase()}')),
                const ButtonSegment(value: JobSearchLevel.city, label: Text('Each city')),
              ],
              selected: {selection.level},
              onSelectionChanged: (v) => cubit.setLevel(selection.code, v.first),
              style: SegmentedButton.styleFrom(selectedBackgroundColor: AppTheme.primary100, selectedForegroundColor: AppTheme.primary800, backgroundColor: AppTheme.surface),
            ),
            if (selection.level != JobSearchLevel.country) ...[
              const SizedBox(height: 16),
              _RegionPicker(selection: selection, noun: noun, regions: regions, loading: state.loadingGeo.contains('regions:${selection.code}')),
            ],
            if (selection.level == JobSearchLevel.city) ...[
              const SizedBox(height: 16),
              _CityPicker(selection: selection, noun: noun, regions: regions, state: state),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: selection.includeRemote,
              activeThumbColor: AppTheme.primary500,
              title: Text('Also search remote jobs open in ${selection.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              onChanged: (v) => cubit.setIncludeRemote(selection.code, v),
            ),
          ],
        ],
      ),
    );
  }
}

class _RegionPicker extends StatefulWidget {
  const _RegionPicker({required this.selection, required this.noun, required this.regions, required this.loading});

  final JobCountrySelection selection;
  final String noun;
  final List<JobRegion>? regions;
  final bool loading;

  @override
  State<_RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends State<_RegionPicker> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobsSearchCubit>();
    final sel = widget.selection;
    final regions = widget.regions ?? const <JobRegion>[];
    final noun = widget.noun.toLowerCase();
    final shown = _filter.isEmpty ? regions : regions.where((r) => r.name.toLowerCase().contains(_filter.toLowerCase())).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(label: Text('All ${regions.isEmpty ? '' : '${regions.length} '}${noun}s'), selected: sel.allRegions, onSelected: (_) => cubit.setAllRegions(sel.code)),
            ChoiceChip(label: Text('Choose ${noun}s${sel.allRegions ? '' : ' (${sel.regions.length})'}'), selected: !sel.allRegions, onSelected: (_) => cubit.pickRegions(sel.code)),
            if (!sel.allRegions) ...[
              TextButton(onPressed: () => cubit.selectAllListedRegions(sel.code), child: const Text('Select all')),
              TextButton(onPressed: () => cubit.clearRegions(sel.code), child: const Text('Deselect all')),
            ],
          ],
        ),
        if (!sel.allRegions) ...[
          const SizedBox(height: 10),
          if (regions.length > 14)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(decoration: InputDecoration(hintText: 'Filter ${noun}s', prefixIcon: const Icon(AppIcons.search, size: 16), isDense: true), onChanged: (v) => setState(() => _filter = v)),
            ),
          if (widget.loading) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in shown)
                FilterChip(
                  label: Text(r.name),
                  selected: sel.regions.contains(r.name),
                  showCheckmark: false,
                  selectedColor: AppTheme.primary100,
                  onSelected: (_) => cubit.toggleRegion(sel.code, r.name),
                ),
            ]),
          if (sel.regions.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Choose at least one $noun, or switch to "All ${noun}s".', style: TextStyle(fontSize: 12.5, color: AppTheme.primary700, fontWeight: FontWeight.w600))),
        ],
      ],
    );
  }
}

class _CityPicker extends StatelessWidget {
  const _CityPicker({required this.selection, required this.noun, required this.regions, required this.state});

  final JobCountrySelection selection;
  final String noun;
  final List<JobRegion>? regions;
  final JobsSearchState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobsSearchCubit>();
    final sel = selection;
    final nounLower = noun.toLowerCase();
    // Cities can only be picked inside regions that are part of the search.
    final inScope = (regions ?? const <JobRegion>[]).where((r) => sel.allRegions || sel.regions.contains(r.name)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(label: Text('All cities in the selected ${nounLower}s'), selected: sel.allCities, onSelected: (_) => cubit.setAllCities(sel.code)),
            ChoiceChip(label: Text('Choose cities${sel.allCities ? '' : ' (${sel.cities.length})'}'), selected: !sel.allCities, onSelected: (_) => cubit.pickCities(sel.code)),
          ],
        ),
        if (sel.allCities)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              sel.allRegions ? 'Every city in the dataset — this can be thousands of searches. The summary shows the exact number.' : 'Every city in the chosen ${nounLower}s.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else ...[
          const SizedBox(height: 10),
          if (inScope.isEmpty)
            Text('Choose ${nounLower}s above first, then pick cities inside them.', style: Theme.of(context).textTheme.bodySmall)
          else if (inScope.length > 60)
            Text('Choose fewer than 60 ${nounLower}s to pick cities inside them, or keep "All cities".', style: Theme.of(context).textTheme.bodySmall)
          else
            Container(
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radius)),
              child: Column(children: [
                for (final r in inScope)
                  _RegionCities(
                    selection: sel,
                    region: r,
                    list: state.cities[JobsSearchState.cityKey(sel.code, r.name)],
                    loading: state.loadingGeo.contains(JobsSearchState.cityKey(sel.code, r.name)),
                  ),
              ]),
            ),
        ],
      ],
    );
  }
}

class _RegionCities extends StatefulWidget {
  const _RegionCities({required this.selection, required this.region, required this.list, required this.loading});

  final JobCountrySelection selection;
  final JobRegion region;
  final JobCityList? list;
  final bool loading;

  @override
  State<_RegionCities> createState() => _RegionCitiesState();
}

class _RegionCitiesState extends State<_RegionCities> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<JobsSearchCubit>();
    final sel = widget.selection;
    final region = widget.region;
    final picked = sel.cities.where((p) => p.state == region.name).length;
    final cities = widget.list?.cities ?? const <JobCity>[];
    final shown = _filter.isEmpty ? cities : cities.where((c) => c.name.toLowerCase().contains(_filter.toLowerCase())).toList();
    return ExpansionTile(
      // A plain key: a PageStorageKey here would share its storage bucket with the list inside
      // and the two would read each other's saved state (a bool vs a scroll offset).
      key: ValueKey('cities-${sel.code}-${region.name}'),
      shape: const Border(),
      collapsedShape: const Border(),
      onExpansionChanged: (open) => open ? cubit.loadCities(sel.code, region.name) : null,
      title: Text(region.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      subtitle: Text('$picked of ${thousands(region.cityCount)} cities', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        if (widget.loading || widget.list == null)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else ...[
          Row(children: [
            Expanded(child: TextField(decoration: const InputDecoration(hintText: 'Find a city', prefixIcon: Icon(AppIcons.search, size: 16), isDense: true), onChanged: (v) => setState(() => _filter = v))),
            TextButton(onPressed: () => cubit.selectRegionCities(sel.code, region.name, selected: true), child: const Text('Select all')),
            TextButton(onPressed: () => cubit.selectRegionCities(sel.code, region.name, selected: false), child: const Text('Clear')),
          ]),
          SizedBox(
            height: (shown.length * 40.0).clamp(40, 260),
            child: ListView.builder(
              itemCount: shown.length,
              itemExtent: 40,
              itemBuilder: (context, i) {
                final c = shown[i];
                final on = sel.cities.contains(JobCityPick(region.name, c.name));
                return CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppTheme.primary500,
                  contentPadding: EdgeInsets.zero,
                  value: on,
                  title: Text(c.name, style: const TextStyle(fontSize: 14)),
                  secondary: c.population > 0 ? Text(_population(c.population), style: TextStyle(fontSize: 12, color: AppTheme.textMuted)) : null,
                  onChanged: (_) => cubit.toggleCity(sel.code, region.name, c.name),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  String _population(int p) => p >= 1000000 ? '${(p / 1000000).toStringAsFixed(1)}M' : (p >= 1000 ? '${(p / 1000).round()}k' : '$p');
}
