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
      if (user == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in failed or cancelled')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: Stack(
        children: [
          // Soft decorative blobs bleeding off the page edges.
          Positioned(
            top: -90,
            right: -70,
            child: _Blob(size: 240, color: t.accentTint),
          ),
          Positioned(
            top: 90,
            right: 40,
            child: _Blob(size: 72, color: t.sageTintStrong),
          ),
          Positioned(
            bottom: -120,
            left: -90,
            child: _Blob(size: 280, color: t.sageTint),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 2),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: t.sageTintStrong,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(AppIcons.sprout, size: 36, color: t.sageText),
                  ),
                  const SizedBox(height: 28),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Grow your\n'),
                        TextSpan(
                          text: 'next lead.',
                          style: TextStyle(color: t.accentDeep),
                        ),
                      ],
                    ),
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sign in to access your business leads and outreach tools.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  _FeatureRow(
                    icon: AppIcons.compass,
                    tint: t.accentTint,
                    iconColor: t.accentText,
                    label: 'Fresh leads, straight from your searches',
                  ),
                  const SizedBox(height: 12),
                  _FeatureRow(
                    icon: AppIcons.chat,
                    tint: t.sageTint,
                    iconColor: t.sageText,
                    label: 'One-tap WhatsApp outreach',
                  ),
                  const SizedBox(height: 12),
                  _FeatureRow(
                    icon: AppIcons.handshake,
                    tint: t.accentTint,
                    iconColor: t.accentText,
                    label: 'Track every deal to the finish',
                  ),
                  const Spacer(flex: 3),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _handleGoogleSignIn,
                        icon: const Icon(AppIcons.logIn, size: 20),
                        label: const Text('Sign in with Google'),
                      ),
                    ),
                  const SizedBox(height: 48),
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
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
