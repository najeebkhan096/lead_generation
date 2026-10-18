import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;
  final _authService = AuthService();

  Future<void> _handleGoogleSignIn() async {
    setState(() => _loading = true);
    try {
      final user = await _authService.signInWithGoogle();
      // Backing out of the Google account picker is not an error: say
      // nothing. Only a real failure gets a message.
      final reason = _authService.lastError;
      if (user == null && reason != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Stack(
        children: [
          // A quiet indigo wash at the top that fades into the page.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 360,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [t.accentTint, t.ground],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 2),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard + 2),
                    ),
                    child: Icon(AppIcons.send, size: 30, color: t.onFill),
                  ),
                  const SizedBox(height: 28),
                  Text('Verified leads,\nready to contact.', style: text.displaySmall),
                  const SizedBox(height: 12),
                  Text(
                    'Sign in to see the businesses confirmed on WhatsApp, and track who you have reached.',
                    style: text.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  Container(
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      border: Border.all(color: t.border),
                    ),
                    child: Column(
                      children: [
                        _FeatureRow(
                          icon: AppIcons.chat,
                          tint: t.sageTint,
                          iconColor: t.sageText,
                          label: 'Numbers confirmed on WhatsApp',
                        ),
                        Divider(color: t.border, height: 1),
                        _FeatureRow(
                          icon: AppIcons.handshake,
                          tint: t.neutralTint,
                          iconColor: t.subtle,
                          label: 'New and contacted, always in order',
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 3),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                        onPressed: _handleGoogleSignIn,
                        icon: const Icon(AppIcons.logIn, size: 20),
                        label: const Text('Sign in with Google'),
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppTheme.radius)),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
