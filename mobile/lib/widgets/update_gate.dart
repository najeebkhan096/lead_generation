import 'package:flutter/material.dart';

import '../pages/update_required_page.dart';
import '../services/app_update.dart';
import 'brand_splash.dart';

/// Runs the update check once at startup. When this install is too old, it
/// shows [UpdateRequiredPage] instead of [child]; otherwise it shows [child].
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child, this.check});

  final Widget child;

  /// For tests; defaults to the real check against Firestore.
  final AppUpdateCheck? check;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  late final AppUpdateCheck _check = widget.check ?? AppUpdateCheck();
  late final Future<AppUpdateRule?> _required = _check.requiredUpdate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUpdateRule?>(
      future: _required,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const BrandSplash(key: ValueKey('update-check'), message: 'Checking for updates…');
        }
        final rule = snapshot.data;
        if (rule != null) return UpdateRequiredPage(key: const ValueKey('update-required'), rule: rule);
        return widget.child;
      },
    );
  }
}
