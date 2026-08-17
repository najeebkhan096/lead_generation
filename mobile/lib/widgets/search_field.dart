import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The same search bar used across every list page — a real tappable
/// search button (not a decorative icon) that dismisses the keyboard,
/// plus a clear button once there's text. Filtering itself stays live
/// as-you-type via [onChanged]; the button doesn't gate it.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.value,
    required this.onChanged,
    this.hintText = 'Search...',
  });

  final TextEditingController controller;
  final String value;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: IconButton(
          padding: const EdgeInsets.only(left: 12, right: 4),
          constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          tooltip: 'Search',
          icon: Icon(AppIcons.search, size: 19, color: t.faint),
          onPressed: () => FocusScope.of(context).unfocus(),
        ),
        suffixIcon: value.isNotEmpty
            ? IconButton(
                icon: const Icon(AppIcons.x, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}
