import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';

/// The state portion of a location string — "Austin, TX" → "TX", a bare
/// "Texas" stays as is. Archive leads carry whatever the scraper put in
/// `location`, so this is the grouping key for the state picker.
String stateLabelOf(String location) {
  final loc = location.trim();
  if (loc.isEmpty) return 'Unknown';
  final comma = loc.lastIndexOf(',');
  return (comma >= 0 ? loc.substring(comma + 1) : loc).trim();
}

/// Distinct states in [leads] with how many businesses each has, sorted by
/// name — the chips [StateScopeSection] offers.
List<({String name, int count})> statesIn(List<Lead> leads) {
  final counts = <String, int>{};
  for (final l in leads) {
    final name = stateLabelOf(l.location);
    counts[name] = (counts[name] ?? 0) + 1;
  }
  final names = counts.keys.toList()..sort();
  return [for (final n in names) (name: n, count: counts[n]!)];
}

/// "All states / Selected states" scope picker used by the Excel Archive
/// validators (WhatsApp and email) to limit a run to chosen states.
class StateScopeSection extends StatelessWidget {
  const StateScopeSection({
    super.key,
    required this.states,
    required this.allStates,
    required this.selected,
    required this.enabled,
    required this.onAllChanged,
    required this.onToggle,
  });

  final List<({String name, int count})> states;
  final bool allStates;
  final Set<String> selected;
  final bool enabled;
  final ValueChanged<bool> onAllChanged;
  final void Function(String name, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    if (states.isEmpty) return const SizedBox.shrink();
    final selectedCount = allStates
        ? states.fold<int>(0, (s, l) => s + l.count)
        : states.where((l) => selected.contains(l.name)).fold<int>(0, (s, l) => s + l.count);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('States', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
            'Validate every business in this category, or only the states you pick.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.faint),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('All states'), icon: Icon(AppIcons.globe, size: 16)),
              ButtonSegment(value: false, label: Text('Selected states'), icon: Icon(AppIcons.mapPin, size: 16)),
            ],
            selected: {allStates},
            onSelectionChanged: enabled ? (next) => onAllChanged(next.first) : null,
          ),
          if (!allStates) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final loc in states)
                  FilterChip(
                    label: Text('${loc.name} (${loc.count})'),
                    selected: selected.contains(loc.name),
                    onSelected: enabled ? (v) => onToggle(loc.name, v) : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              selected.isEmpty
                  ? 'Pick one or more states to validate.'
                  : 'Will check $selectedCount business${selectedCount == 1 ? '' : 'es'} in ${selected.length} state${selected.length == 1 ? '' : 's'}.',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.faint, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
