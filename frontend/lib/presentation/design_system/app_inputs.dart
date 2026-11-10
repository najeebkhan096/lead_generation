import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// A field label above its control (never floating), plus an optional hint and
/// validation message below. Shared by every input in this file.
class FieldShell extends StatelessWidget {
  const FieldShell({super.key, this.label, this.helper, this.error, this.required = false, required this.child});

  final String? label;
  final String? helper;
  final String? error;
  final bool required;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text.rich(
            TextSpan(
              text: label,
              children: [if (required) TextSpan(text: ' *', style: TextStyle(color: AppTheme.error))],
            ),
            style: text.labelMedium?.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
        ],
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(AppIcons.alert, size: 13, color: AppTheme.error),
            const SizedBox(width: 5),
            Expanded(child: Text(error!, style: text.bodySmall?.copyWith(color: AppTheme.error600))),
          ]),
        ] else if (helper != null) ...[
          const SizedBox(height: 6),
          Text(helper!, style: text.bodySmall),
        ],
      ],
    );
  }
}

/// A single- or multi-line text field with the label above it.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.enabled = true,
    this.required = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.focusNode,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;
  final String? error;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final bool enabled;
  final bool required;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return FieldShell(
      label: label,
      helper: helper,
      error: error,
      required: required,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        obscureText: obscureText,
        enabled: enabled,
        autofocus: autofocus,
        maxLines: obscureText ? 1 : maxLines,
        minLines: minLines,
        textInputAction: textInputAction,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 17),
          suffixIcon: suffix,
          enabledBorder: error == null ? null : OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radius), borderSide: BorderSide(color: AppTheme.error)),
        ),
      ),
    );
  }
}

/// A compact search box (40px) with a clear button.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.hint = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onCleared;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _own;

  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        onChanged: (v) {
          setState(() {});
          widget.onChanged?.call(v);
        },
        onSubmitted: widget.onSubmitted,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(AppIcons.search, size: 17),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(AppIcons.close, size: 15),
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                    widget.onChanged?.call('');
                    widget.onCleared?.call();
                  },
                ),
        ),
      ),
    );
  }
}

/// One entry of an [AppDropdown] / [AppMultiSelect].
class AppOption<T> {
  const AppOption(this.value, this.label, {this.icon, this.caption});

  final T value;
  final String label;
  final IconData? icon;

  /// A secondary right-aligned count or note ("1,204").
  final String? caption;
}

/// A single-choice dropdown: label above, menu below, current value kept in
/// the parent (controlled).
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint = 'Select',
    this.helper,
    this.error,
    this.leadingIcon,
    this.enabled = true,
    this.required = false,
    this.width,
  });

  final List<AppOption<T>> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final String? label;
  final String hint;
  final String? helper;
  final String? error;
  final IconData? leadingIcon;
  final bool enabled;
  final bool required;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((o) => o.value == value).firstOrNull;
    final field = _MenuField(
      width: width,
      enabled: enabled && onChanged != null,
      leadingIcon: leadingIcon,
      text: selected?.label,
      hint: hint,
      hasError: error != null,
      menuChildren: (close) => [
        for (final o in options)
          MenuItemButton(
            onPressed: () => onChanged?.call(o.value),
            leadingIcon: o.icon != null ? Icon(o.icon, size: 16) : null,
            trailingIcon: o.value == value ? Icon(AppIcons.check, size: 16, color: AppTheme.primary) : null,
            style: _itemStyle(selected: o.value == value),
            child: _OptionLabel(o),
          ),
      ],
    );
    return FieldShell(label: label, helper: helper, error: error, required: required, child: field);
  }
}

/// A multiple-choice dropdown; the menu stays open while ticking options.
class AppMultiSelect<T> extends StatelessWidget {
  const AppMultiSelect({
    super.key,
    required this.options,
    required this.values,
    required this.onChanged,
    this.label,
    this.hint = 'Select',
    this.helper,
    this.error,
    this.leadingIcon,
    this.enabled = true,
    this.required = false,
    this.width,
  });

  final List<AppOption<T>> options;
  final Set<T> values;
  final ValueChanged<Set<T>>? onChanged;
  final String? label;
  final String hint;
  final String? helper;
  final String? error;
  final IconData? leadingIcon;
  final bool enabled;
  final bool required;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final picked = options.where((o) => values.contains(o.value)).toList();
    final summary = picked.isEmpty ? null : (picked.length <= 2 ? picked.map((o) => o.label).join(', ') : '${picked.length} selected');
    final field = _MenuField(
      width: width,
      enabled: enabled && onChanged != null,
      leadingIcon: leadingIcon,
      text: summary,
      hint: hint,
      hasError: error != null,
      menuChildren: (close) => [
        for (final o in options)
          MenuItemButton(
            closeOnActivate: false,
            onPressed: () {
              final next = {...values};
              next.contains(o.value) ? next.remove(o.value) : next.add(o.value);
              onChanged?.call(next);
            },
            leadingIcon: IgnorePointer(
              child: SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(value: values.contains(o.value), onChanged: (_) {}),
              ),
            ),
            style: _itemStyle(selected: values.contains(o.value)),
            child: _OptionLabel(o),
          ),
      ],
    );
    return FieldShell(label: label, helper: helper, error: error, required: required, child: field);
  }
}

ButtonStyle _itemStyle({required bool selected}) => ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(160, 38)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      foregroundColor: WidgetStatePropertyAll(selected ? AppTheme.primary700 : AppTheme.textPrimary),
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)) return AppTheme.neutral100;
        return selected ? AppTheme.primary100.withValues(alpha: 0.5) : Colors.transparent;
      }),
      textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSm))),
    );

class _OptionLabel<T> extends StatelessWidget {
  const _OptionLabel(this.option);

  final AppOption<T> option;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(option.label, overflow: TextOverflow.ellipsis)),
        if (option.caption != null) ...[
          const SizedBox(width: 16),
          Text(option.caption!, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        ],
      ],
    );
  }
}

/// The closed field + anchored menu behind both dropdowns.
class _MenuField extends StatelessWidget {
  const _MenuField({
    required this.width,
    required this.enabled,
    required this.leadingIcon,
    required this.text,
    required this.hint,
    required this.hasError,
    required this.menuChildren,
  });

  final double? width;
  final bool enabled;
  final IconData? leadingIcon;
  final String? text;
  final String hint;
  final bool hasError;
  final List<Widget> Function(VoidCallback close) menuChildren;

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final menuWidth = constraints.hasBoundedWidth ? constraints.maxWidth : (width ?? 240);
        return MenuAnchor(
          crossAxisUnconstrained: false,
          style: MenuStyle(
            minimumSize: WidgetStatePropertyAll(Size(menuWidth, 0)),
            maximumSize: const WidgetStatePropertyAll(Size(480, 360)),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
          ),
          menuChildren: menuChildren(() {}),
          builder: (context, controller, _) {
            final open = controller.isOpen;
            return Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                onTap: enabled ? () => open ? controller.close() : controller.open() : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: enabled ? AppTheme.surface : AppTheme.neutral100,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(
                      color: hasError ? AppTheme.error : (open ? AppTheme.primary : AppTheme.borderStrong),
                      width: open ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (leadingIcon != null) ...[
                        Icon(leadingIcon, size: 16, color: AppTheme.textMuted),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          text ?? hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: text == null ? AppTheme.textMuted : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(AppIcons.chevronDown, size: 16, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    return width == null ? body : SizedBox(width: width, child: body);
  }
}

/// A checkbox with a label and optional caption.
class AppCheckboxTile extends StatelessWidget {
  const AppCheckboxTile({super.key, required this.value, required this.onChanged, required this.label, this.caption});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(value: value, onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: text.bodyMedium?.copyWith(color: AppTheme.textPrimary)),
                  if (caption != null) Text(caption!, style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
