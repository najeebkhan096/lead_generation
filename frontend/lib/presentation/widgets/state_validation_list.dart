import 'package:flutter/material.dart';

import '../../domain/entities/whatsapp_web_status.dart';
import '../design_system/design_system.dart';

/// The states of a lead list with their validation progress, and a way to pick
/// which to validate: a checkbox per state with one "Validate selected" action,
/// a "Validate" button on every state, and "Validate all".
///
/// A state with nothing left to check has its button disabled, so it is not run
/// again. [unit] is what a check applies to ("number", "business"), [foundLabel]
/// the positive answer ("on WhatsApp", "with an email").
class StateValidationList extends StatelessWidget {
  const StateValidationList({
    super.key,
    required this.summary,
    required this.selected,
    required this.enabled,
    required this.unit,
    required this.foundLabel,
    required this.onToggle,
    required this.onToggleAll,
    required this.onValidate,
    this.includeChecked = false,
  });

  final UnvalidatedWhatsAppSummary summary;
  final Set<String> selected;

  /// False while a run is going or starting.
  final bool enabled;
  final String unit;
  final String foundLabel;

  /// When true every state with something to check is runnable, even one that
  /// is already validated (a re-check).
  final bool includeChecked;

  final void Function(String name, bool selected) onToggle;
  final ValueChanged<bool> onToggleAll;

  /// Runs the given states; `null` means every state.
  final void Function(List<String>? states) onValidate;

  bool _runnable(UnvalidatedLocationCount l) => includeChecked ? l.withPhone > 0 : l.count > 0;

  /// What a run over [l] would work through.
  int _workOf(UnvalidatedLocationCount l) => includeChecked ? l.withPhone : l.count;

  String _plural(int n) => '$n $unit${n == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final runnable = summary.locations.where(_runnable).toList();
    final chosen = runnable.where((l) => selected.contains(l.name)).toList();
    final chosenWork = chosen.fold<int>(0, (sum, l) => sum + _workOf(l));
    final allWork = runnable.fold<int>(0, (sum, l) => sum + _workOf(l));
    final allChosen = runnable.isNotEmpty && chosen.length == runnable.length;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 190,
              child: AppCheckboxTile(
                value: allChosen,
                onChanged: enabled && runnable.isNotEmpty ? onToggleAll : null,
                label: 'Select all states',
              ),
            ),
            AppButton.primary(
              label: chosen.isEmpty ? 'Validate selected' : 'Validate selected (${chosen.length})',
              icon: AppIcons.mapPin,
              size: AppButtonSize.sm,
              onPressed: enabled && chosen.isNotEmpty ? () => onValidate([for (final l in chosen) l.name]) : null,
            ),
            AppButton.outlined(
              label: 'Validate all${allWork > 0 ? ' · ${_plural(allWork)}' : ''}',
              icon: AppIcons.globe,
              size: AppButtonSize.sm,
              onPressed: enabled && allWork > 0 ? () => onValidate(null) : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          chosen.isEmpty
              ? 'Tick the states to validate, or use the button on a state.'
              : 'Will check ${_plural(chosenWork)} in ${chosen.length} state${chosen.length == 1 ? '' : 's'}.',
          style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpace.sm),
        for (final l in summary.locations) _row(context, l),
      ],
    );
  }

  Widget _row(BuildContext context, UnvalidatedLocationCount l) {
    final text = Theme.of(context).textTheme;
    final (label, tone) = switch (l.status) {
      'validated' => ('Validated · ${l.checked} of ${l.withPhone} checked · ${l.found} $foundLabel', AppTone.success),
      'partial' => ('Partly validated · ${l.checked} of ${l.withPhone} checked · ${l.found} $foundLabel', AppTone.warning),
      'no_phone' => ('No ${unit}s to check', AppTone.neutral),
      _ => ('Not validated · ${_plural(l.withPhone)} to check', AppTone.neutral),
    };
    final buttonLabel = switch (l.status) {
      _ when includeChecked && l.withPhone > 0 => l.status == 'validated' ? 'Re-check' : 'Validate',
      'validated' => 'Validated',
      'partial' => 'Validate ${l.count} left',
      'no_phone' => 'Nothing to check',
      _ => 'Validate',
    };
    final canRun = enabled && _runnable(l);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Checkbox(
              value: selected.contains(l.name),
              onChanged: canRun ? (v) => onToggle(l.name, v ?? false) : null,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${l.name} · ${l.total}', style: text.titleSmall),
                const SizedBox(height: 2),
                Text(label, style: text.bodySmall?.copyWith(color: tone.onSurface, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          AppButton.outlined(
            label: buttonLabel,
            size: AppButtonSize.sm,
            onPressed: canRun ? () => onValidate([l.name]) : null,
          ),
        ],
      ),
    );
  }
}
