import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/whatsapp_check_result.dart';
import '../../domain/repositories/lead_repository.dart';

/// Lets a user type a phone number, validates its format, and hands them a
/// wa.me deep link to confirm WhatsApp registration directly in WhatsApp.
///
/// WhatsApp does not expose registration status through any public,
/// unauthenticated endpoint, so this page is intentionally honest about
/// what it can and can't confirm rather than guessing.
class WhatsAppCheckerPage extends StatefulWidget {
  const WhatsAppCheckerPage({super.key});

  @override
  State<WhatsAppCheckerPage> createState() => _WhatsAppCheckerPageState();
}

enum _CheckStatus { idle, loading, success, failure }

class _WhatsAppCheckerPageState extends State<WhatsAppCheckerPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  _CheckStatus _status = _CheckStatus.idle;
  WhatsAppCheckResult? _result;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Enter a phone number';
    if (digits.length < 10) return 'Enter a valid phone number with country/area code';
    return null;
  }

  Future<void> _check() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _status = _CheckStatus.loading;
      _result = null;
      _error = null;
    });

    try {
      final result = await context
          .read<LeadRepository>()
          .checkWhatsAppNumber(_phoneController.text.trim());
      if (!mounted) return;
      setState(() {
        _status = _CheckStatus.success;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _CheckStatus.failure;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openChat(String? waLink) async {
    if (waLink == null) return;
    final uri = Uri.tryParse(waLink);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final loading = _status == _CheckStatus.loading;

    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp Checker')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF0F4F8), Color(0xFFE8F5F3), Color(0xFFF7F3EB)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'WhatsApp Checker',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enter a phone number with country code (e.g. +1 415 555 0100). '
                        'WhatsApp doesn\'t expose registration status publicly, so we '
                        'validate the number and hand you a direct link to confirm in WhatsApp.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        enabled: !loading,
                        decoration: const InputDecoration(
                          labelText: 'Phone number',
                          hintText: '+14155550100',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        validator: _validatePhone,
                        onFieldSubmitted: (_) => loading ? null : _check(),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: loading ? null : _check,
                        child: loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Validate Number'),
                      ),
                      const SizedBox(height: 24),
                      if (_status == _CheckStatus.success && _result != null)
                        _ResultCard(result: _result!, onOpenChat: _openChat),
                      if (_status == _CheckStatus.failure && _error != null)
                        _ErrorCard(message: _error!),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onOpenChat});

  final WhatsAppCheckResult result;
  final Future<void> Function(String? waLink) onOpenChat;

  @override
  Widget build(BuildContext context) {
    final valid = result.validFormat;
    final color = valid ? AppTheme.accent : const Color(0xFFB91C1C);
    final bg = valid ? AppTheme.accentSoft : const Color(0xFFFEE2E2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                valid ? Icons.check_circle_outline : Icons.cancel_outlined,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  valid ? 'Valid phone number format' : 'Invalid phone number',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
                ),
              ),
            ],
          ),
          if (result.e164 != null) ...[
            const SizedBox(height: 8),
            Text('Number: +${result.e164}', style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (valid && result.waLink != null) ...[
            const SizedBox(height: 10),
            Text(
              'This confirms the format only. Tap below to open WhatsApp — '
              'it will tell you directly if this number isn\'t registered.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => onOpenChat(result.waLink),
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('Open in WhatsApp to Verify'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB91C1C).withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFB91C1C)),
      ),
    );
  }
}
