import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

/// The Jobs section's building blocks, in the console's existing language:
/// cream surfaces, rounded cards, pills, terracotta accents.

class JobsCard extends StatelessWidget {
  const JobsCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.border, this.color, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? border;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: child,
    );
    if (onTap == null) return decorated;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(AppTheme.radiusCard), onTap: onTap, child: decorated),
    );
  }
}

class JobsSectionTitle extends StatelessWidget {
  const JobsSectionTitle(this.title, {super.key, this.subtitle, this.trailing, this.icon});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppTheme.primary100, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: AppTheme.primary700),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A selectable pill, sized to its text (quick views, segmented choices).
class JobChoicePill extends StatelessWidget {
  const JobChoicePill({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.primary100 : AppTheme.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppTheme.primary300 : AppTheme.neutral200)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: selected ? AppTheme.primary800 : AppTheme.textPrimary)),
        ),
      ),
    );
  }
}

enum _PillTone { neutral, accent, sage }

/// A small rounded label. Colors resolve at build time so the pill follows the
/// light / dark theme.
class JobPill extends StatelessWidget {
  const JobPill(this.label, {super.key, this.icon, this.background, this.foreground, this.dense = false}) : _tone = _PillTone.neutral;

  const JobPill.accent(this.label, {super.key, this.icon, this.dense = false})
      : background = null,
        foreground = null,
        _tone = _PillTone.accent;

  const JobPill.sage(this.label, {super.key, this.icon, this.dense = false})
      : background = null,
        foreground = null,
        _tone = _PillTone.sage;

  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;
  final bool dense;
  final _PillTone _tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (_tone) {
      _PillTone.accent => (AppTheme.primary100, AppTheme.primary800),
      _PillTone.sage => (AppTheme.success100, AppTheme.success700),
      _PillTone.neutral => (AppTheme.neutral100, AppTheme.neutral700),
    };
    final background = this.background ?? bg;
    final foreground = this.foreground ?? fg;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: dense ? 11 : 13, color: foreground), SizedBox(width: dense ? 4 : 5)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class JobStatTile extends StatelessWidget {
  const JobStatTile({super.key, required this.icon, required this.label, required this.value, this.tint, this.iconColor, this.onTap, this.hint});

  final IconData icon;
  final String label;
  final String value;
  final String? hint;
  final Color? tint;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return JobsCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tint ?? AppTheme.primary100, shape: BoxShape.circle),
            child: Icon(icon, size: 17, color: iconColor ?? AppTheme.primary700),
          ),
          const SizedBox(height: 14),
          // A count of hundreds of thousands must shrink to fit the tile, never wrap.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, height: 1)),
          ),
          const SizedBox(height: 5),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
          ],
        ],
      ),
    );
  }
}

class JobsEmpty extends StatelessWidget {
  const JobsEmpty({super.key, required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: AppTheme.primary100, shape: BoxShape.circle),
                child: Icon(icon, size: 28, color: AppTheme.primary700),
              ),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class JobsErrorBanner extends StatelessWidget {
  const JobsErrorBanner(this.message, {super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.primary100, borderRadius: BorderRadius.circular(AppTheme.radius), border: Border.all(color: AppTheme.primary300)),
      child: Row(
        children: [
          Icon(AppIcons.alert, size: 18, color: AppTheme.primary700),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: TextStyle(fontSize: 13.5, color: AppTheme.primary800, fontWeight: FontWeight.w600))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Shows a bloc's transient `message` as a snackbar, once, then asks the bloc
/// to clear it. [read] pulls the message from the state; [clear] resets it.
class JobsMessageListener<B extends StateStreamable<S>, S> extends StatelessWidget {
  const JobsMessageListener({super.key, required this.read, required this.clear, required this.child, this.isError});

  final String? Function(S state) read;
  final bool Function(S state)? isError;
  final void Function(B bloc) clear;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<B, S>(
      listenWhen: (a, b) => read(b) != null && read(a) != read(b),
      listener: (context, state) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final error = isError?.call(state) ?? false;
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(read(state)!),
            backgroundColor: error ? AppTheme.primary800 : null,
            duration: Duration(seconds: error ? 6 : 3),
          ));
        clear(context.read<B>());
      },
      child: child,
    );
  }
}

/// A text field that turns what is typed into removable chips — job titles and keywords.
class JobsChipInput extends StatefulWidget {
  const JobsChipInput({super.key, required this.label, required this.hint, required this.values, required this.onAdd, required this.onRemove, this.maxItems = 40});

  final String label;
  final String hint;
  final List<String> values;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final int maxItems;

  @override
  State<JobsChipInput> createState() => _JobsChipInputState();
}

class _JobsChipInputState extends State<JobsChipInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit([String? _]) {
    // Commas and new lines separate several entries pasted at once.
    for (final part in _controller.text.split(RegExp(r'[,\n;]'))) {
      if (part.trim().isNotEmpty && widget.values.length < widget.maxItems) widget.onAdd(part.trim());
    }
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
                onSubmitted: _submit,
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              tooltip: 'Add',
              onPressed: _submit,
              icon: const Icon(AppIcons.plus, size: 18),
              style: IconButton.styleFrom(backgroundColor: AppTheme.primary500, foregroundColor: AppTheme.onPrimary, padding: const EdgeInsets.all(14)),
            ),
          ],
        ),
        if (widget.values.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in widget.values)
                InputChip(
                  label: Text(v),
                  onDeleted: () => widget.onRemove(v),
                  deleteIconColor: AppTheme.primary700,
                  backgroundColor: AppTheme.primary100,
                  labelStyle: TextStyle(color: AppTheme.primary800, fontWeight: FontWeight.w700, fontSize: 13),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A dropdown whose first entry means "no filter".
class JobsDropdown<T> extends StatelessWidget {
  const JobsDropdown({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.anyLabel = 'Any'});

  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  final String anyLabel;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T?>(
      initialValue: items.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      items: [
        DropdownMenuItem<T?>(value: null, child: Text(anyLabel)),
        for (final e in items.entries) DropdownMenuItem<T?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

Future<void> openExternal(BuildContext context, String? url) async {
  final uri = url == null ? null : Uri.tryParse(url);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (uri == null || !uri.hasScheme || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    messenger?.showSnackBar(const SnackBar(content: Text('Could not open that link.')));
  }
}

/// "just now", "12 min ago", "3 h ago", "5 d ago", then a date.
String relativeTime(DateTime? t, {DateTime? now}) {
  if (t == null) return '—';
  final d = (now ?? DateTime.now()).difference(t.toLocal());
  if (d.isNegative || d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 30) return '${d.inDays} d ago';
  final l = t.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

String durationLabel(Duration? d) {
  if (d == null) return '—';
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inHours}h ${d.inMinutes % 60}m';
}

/// A readable name for a source id: `career_page` → "Career pages".
String sourceLabel(String id) => switch (id) {
      'career_page' => 'Career pages',
      'adzuna' => 'Adzuna',
      'jooble' => 'Jooble',
      'remotive' => 'Remotive',
      'greenhouse' => 'Greenhouse',
      'lever' => 'Lever',
      'ashby' => 'Ashby',
      'workable' => 'Workable',
      _ => id.isEmpty ? id : id[0].toUpperCase() + id.substring(1),
    };
