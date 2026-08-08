import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/whatsapp_check_result.dart';
import '../../domain/entities/whatsapp_web_status.dart';
import '../../domain/repositories/lead_repository.dart';

/// WhatsApp Web connection (top) + a single-number format checker
/// (below). Real validation of *other* numbers — the kind used to flag
/// leads — only exists once WhatsApp Web is connected here; the format
/// checker below only ever confirms shape, not registration, which is
/// why it still hands off to a wa.me link instead of a yes/no answer.
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

  WhatsAppWebStatus? _webStatus;
  Timer? _webPollTimer;
  bool _webActionInFlight = false;

  WhatsAppValidationSnapshot? _validationStatus;
  Timer? _validationPollTimer;
  bool _startingValidation = false;

  @override
  void initState() {
    super.initState();
    _pollWebStatus();
    _pollValidationStatus();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _webPollTimer?.cancel();
    _validationPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollWebStatus() async {
    try {
      final status = await context.read<LeadRepository>().getWhatsAppWebStatus();
      if (!mounted) return;
      setState(() => _webStatus = status);
      if (status.status.isConnecting) {
        _webPollTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => _pollWebStatus());
      } else {
        _webPollTimer?.cancel();
        _webPollTimer = null;
      }
    } catch (_) {
      // Backend unreachable — leave last-known status showing.
    }
  }

  Future<void> _pollValidationStatus() async {
    try {
      final status = await context.read<LeadRepository>().getWhatsAppValidationStatus();
      if (!mounted) return;
      setState(() => _validationStatus = status);
      if (status.active) {
        _validationPollTimer ??= Timer.periodic(const Duration(seconds: 3), (_) => _pollValidationStatus());
      } else {
        _validationPollTimer?.cancel();
        _validationPollTimer = null;
      }
    } catch (_) {}
  }

  Future<void> _startAutoValidation() async {
    setState(() => _startingValidation = true);
    try {
      await context.read<LeadRepository>().startWhatsAppAutoValidation();
      await _pollValidationStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _startingValidation = false);
    }
  }

  Future<void> _connectWebSession() async {
    setState(() => _webActionInFlight = true);
    try {
      await context.read<LeadRepository>().connectWhatsAppWeb();
      await _pollWebStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _webActionInFlight = false);
    }
  }

  Future<void> _disconnectWebSession() async {
    setState(() => _webActionInFlight = true);
    try {
      await context.read<LeadRepository>().disconnectWhatsAppWeb();
      await _pollWebStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _webActionInFlight = false);
    }
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
      appBar: AppBar(title: const Text('WhatsApp Tool')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WhatsAppWebConnectionCard(
                    status: _webStatus,
                    busy: _webActionInFlight,
                    onConnect: _connectWebSession,
                    onDisconnect: _disconnectWebSession,
                  ),
                  if (_webStatus?.status == WhatsAppWebConnectionStatus.ready) ...[
                    const SizedBox(height: 16),
                    _AutomationCard(
                      status: _validationStatus,
                      busy: _startingValidation,
                      onStart: _startAutoValidation,
                      onRefresh: _pollValidationStatus,
                    ),
                  ],
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(child: Divider(color: AppTheme.neutral300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Quick format check', style: Theme.of(context).textTheme.bodySmall),
                      ),
                      Expanded(child: Divider(color: AppTheme.neutral300)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Enter a phone number with country code (e.g. +1 415 555 0100). '
                          'This only checks the format — for a real yes/no answer on any '
                          'number, connect WhatsApp Web above and use Validate WhatsApp on '
                          'the Leads page.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          enabled: !loading,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            hintText: '+14155550100',
                            prefixIcon: Icon(AppIcons.phone, size: 19),
                          ),
                          validator: _validatePhone,
                          onFieldSubmitted: (_) => loading ? null : _check(),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: loading ? null : _check,
                          child: loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.2),
                                )
                              : const Text('Check format'),
                        ),
                        const SizedBox(height: 20),
                        if (_status == _CheckStatus.success && _result != null)
                          _ResultCard(result: _result!, onOpenChat: _openChat),
                        if (_status == _CheckStatus.failure && _error != null)
                          _ErrorCard(message: _error!),
                      ],
                    ),
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

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({
    required this.status,
    required this.busy,
    required this.onStart,
    required this.onRefresh,
  });

  final WhatsAppValidationSnapshot? status;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final active = status?.active ?? false;
    final checked = status?.checked ?? 0;
    final total = status?.total ?? 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: active ? AppTheme.sage100 : AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: active ? Border.all(color: AppTheme.sage500, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: active ? AppTheme.sage500 : AppTheme.neutral200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  active ? AppIcons.refresh : AppIcons.zap,
                  size: 19,
                  color: active ? Colors.white : AppTheme.neutral600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? 'Bulk validating leads...' : 'WhatsApp Automation',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active
                          ? 'Checking $checked of $total leads'
                          : 'Discover and check all unvalidated leads from Firestore',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else if (active)
                IconButton(
                  icon: const Icon(AppIcons.refresh, size: 18),
                  onPressed: onRefresh,
                )
              else
                ElevatedButton(
                  onPressed: onStart,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(100, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Start Now'),
                ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? (checked / total).toDouble() : 0,
                minHeight: 6,
                backgroundColor: AppTheme.surface,
                valueColor: const AlwaysStoppedAnimation(AppTheme.sage500),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WhatsAppWebConnectionCard extends StatelessWidget {
  const _WhatsAppWebConnectionCard({
    required this.status,
    required this.busy,
    required this.onConnect,
    required this.onDisconnect,
  });

  final WhatsAppWebStatus? status;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final s = status?.status ?? WhatsAppWebConnectionStatus.disconnected;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: s == WhatsAppWebConnectionStatus.ready ? AppTheme.sage100 : AppTheme.accent100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  s == WhatsAppWebConnectionStatus.ready ? AppIcons.checkCircle : AppIcons.shieldCheck,
                  size: 19,
                  color: s == WhatsAppWebConnectionStatus.ready ? AppTheme.sage700 : AppTheme.accent700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WhatsApp Web connection', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(_subtitleFor(s), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildBody(context, s),
        ],
      ),
    );
  }

  String _subtitleFor(WhatsAppWebConnectionStatus s) {
    switch (s) {
      case WhatsAppWebConnectionStatus.ready:
        return 'Connected — real validation is available';
      case WhatsAppWebConnectionStatus.qr:
        return 'Scan the QR code to link a WhatsApp account';
      case WhatsAppWebConnectionStatus.initializing:
        return 'Starting session…';
      case WhatsAppWebConnectionStatus.authenticated:
        return 'Signed in — finishing setup…';
      case WhatsAppWebConnectionStatus.authFailure:
        return 'Authentication failed';
      case WhatsAppWebConnectionStatus.error:
        return 'Something went wrong';
      case WhatsAppWebConnectionStatus.disconnected:
        return 'Not connected — required for real WhatsApp validation';
    }
  }

  Widget _buildBody(BuildContext context, WhatsAppWebConnectionStatus s) {
    switch (s) {
      case WhatsAppWebConnectionStatus.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.sage100,
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.checkCircle, size: 15, color: AppTheme.sage700),
                  const SizedBox(width: 8),
                  Text(
                    status?.pushname?.isNotEmpty == true
                        ? 'Linked as ${status!.pushname}'
                        : status?.phoneNumber != null
                            ? 'Linked as +${status!.phoneNumber}'
                            : 'Linked',
                    style: const TextStyle(color: AppTheme.sage800, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SafetyStatusPanel(safety: status?.safety ?? const WhatsAppSafetyStatus()),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: busy ? null : onDisconnect,
              icon: const Icon(AppIcons.close, size: 16),
              label: const Text('Disconnect'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
            ),
          ],
        );

      case WhatsAppWebConnectionStatus.qr:
        final qr = status?.qrDataUrl;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (qr != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child: Image.memory(
                  base64Decode(qr.split(',').last),
                  width: 220,
                  height: 220,
                  gaplessPlayback: true,
                ),
              ),
            const SizedBox(height: 14),
            Text(
              'Open WhatsApp on your phone → Settings → Linked Devices → '
              'Link a Device, then scan this code.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: busy ? null : onDisconnect,
              child: const Text('Cancel'),
            ),
          ],
        );

      case WhatsAppWebConnectionStatus.initializing:
      case WhatsAppWebConnectionStatus.authenticated:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            ),
            TextButton(
              onPressed: busy ? null : onDisconnect,
              child: const Text('Cancel'),
            ),
          ],
        );

      case WhatsAppWebConnectionStatus.authFailure:
      case WhatsAppWebConnectionStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (status?.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(status!.error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12.5)),
              ),
            ElevatedButton(onPressed: busy ? null : onConnect, child: const Text('Try again')),
          ],
        );

      case WhatsAppWebConnectionStatus.disconnected:
        return ElevatedButton.icon(
          onPressed: busy ? null : onConnect,
          icon: busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: AppTheme.surface),
                )
              : const Icon(AppIcons.chat, size: 18),
          label: const Text('Connect WhatsApp Web'),
        );
    }
  }
}

/// Shows today's WhatsApp-check budget plus any warm-up/cooldown/circuit
/// state, so it's clear why bulk validation might be slow or blocked.
class _SafetyStatusPanel extends StatelessWidget {
  const _SafetyStatusPanel({required this.safety});

  final WhatsAppSafetyStatus safety;

  @override
  Widget build(BuildContext context) {
    final usedFraction = safety.dailyCap > 0 ? (safety.checksToday / safety.dailyCap).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.neutral100,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.shieldCheck, size: 15, color: AppTheme.neutral600),
              const SizedBox(width: 8),
              Text(
                '${safety.checksToday} / ${safety.dailyCap} checks used today',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppTheme.neutral800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usedFraction,
              minHeight: 5,
              backgroundColor: AppTheme.neutral200,
              valueColor: AlwaysStoppedAnimation(usedFraction >= 1 ? AppTheme.danger : AppTheme.sage500),
            ),
          ),
          if (safety.warmUpActive) ...[
            const SizedBox(height: 10),
            _SafetyBadge(
              icon: AppIcons.clock,
              color: AppTheme.accent700,
              bg: AppTheme.accent100,
              text: 'New device warm-up — ${safety.warmUpDaysRemaining}d left, checks limited & slower',
            ),
          ],
          if (safety.circuitOpen) ...[
            const SizedBox(height: 10),
            _SafetyBadge(
              icon: AppIcons.alert,
              color: AppTheme.danger,
              bg: AppTheme.accent100,
              text: 'Paused after repeated failures — resumes in ${(safety.circuitResetInMs / 60000).ceil()} min',
            ),
          ] else if (safety.cooldownActive) ...[
            const SizedBox(height: 10),
            _SafetyBadge(
              icon: AppIcons.clock,
              color: AppTheme.neutral700,
              bg: AppTheme.neutral200,
              text: 'Cooling down between runs — ${(safety.cooldownRemainingMs / 1000).ceil()}s',
            ),
          ],
        ],
      ),
    );
  }
}

class _SafetyBadge extends StatelessWidget {
  const _SafetyBadge({required this.icon, required this.color, required this.bg, required this.text});

  final IconData icon;
  final Color color;
  final Color bg;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11.5)),
          ),
        ],
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
    final color = valid ? AppTheme.sage700 : AppTheme.danger;
    final bg = valid ? AppTheme.sage100 : AppTheme.accent100;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                valid ? AppIcons.checkCircle : AppIcons.alert,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  valid ? 'Valid phone number format' : 'Invalid phone number',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
          if (result.e164 != null) ...[
            const SizedBox(height: 10),
            Text('Number: +${result.e164}', style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (valid && result.waLink != null) ...[
            const SizedBox(height: 12),
            Text(
              'This confirms the format only. Tap below to open WhatsApp — '
              'it will tell you directly if this number isn\'t registered.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => onOpenChat(result.waLink),
              icon: const Icon(AppIcons.chat, size: 18),
              label: const Text('Open in WhatsApp to Verify'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.sage500,
                foregroundColor: AppTheme.surface,
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.accent100,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600),
      ),
    );
  }
}
