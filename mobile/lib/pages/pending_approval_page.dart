import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Shown to a signed-in user an admin has not approved yet. [onCheckAgain]
/// re-reads the account and returns whether it is approved now (the gate
/// above swaps this page out when it is).
class PendingApprovalPage extends StatefulWidget {
  const PendingApprovalPage({super.key, required this.onCheckAgain});

  final Future<bool> Function() onCheckAgain;

  @override
  State<PendingApprovalPage> createState() => _PendingApprovalPageState();
}

class _PendingApprovalPageState extends State<PendingApprovalPage> {
  bool _checking = false;
  bool _stillWaiting = false;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _stillWaiting = false;
    });
    final approved = await widget.onCheckAgain();
    if (!mounted) return;
    // When approved the gate replaces this page; otherwise say so.
    setState(() {
      _checking = false;
      _stillWaiting = !approved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final email = FirebaseAuth.instance.currentUser?.email;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(color: t.accentTint, shape: BoxShape.circle),
                    child: Icon(AppIcons.hourglass, size: 36, color: t.accentText),
                  ),
                  const SizedBox(height: 28),
                  Text('Waiting for approval', style: text.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(
                    'Your account has been created. An admin needs to approve it before you can see leads. '
                    'Once they do, tap Check again.',
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (email != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                        border: Border.all(color: t.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppIcons.mail, size: 16, color: t.subtle),
                          const SizedBox(width: 8),
                          Flexible(child: Text(email, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: _checking ? null : _check,
                      icon: _checking
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: t.onFill),
                            )
                          : const Icon(AppIcons.refresh, size: 18),
                      label: Text(_checking ? 'Checking…' : 'Check again'),
                    ),
                  ),
                  if (_stillWaiting) ...[
                    const SizedBox(height: 12),
                    Text('Not approved yet.', style: text.bodyMedium?.copyWith(color: t.subtle)),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _checking ? null : () => AuthService().signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
