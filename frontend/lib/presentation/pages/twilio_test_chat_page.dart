import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/twilio_test_lead.dart';
import '../../domain/entities/twilio_test_message.dart';
import '../../domain/repositories/lead_repository.dart';
import '../utils/date_format.dart';
import '../utils/web_image_picker.dart';

/// Conversation with one Twilio test lead: send WhatsApp text, SMS, or the
/// approved template with an image, and watch delivery status and replies.
///
/// This server has no public URL for Twilio's webhooks, so the page asks the
/// backend to pull receipts and replies from Twilio every [pollInterval]
/// while it is open (null turns polling off).
class TwilioTestChatPage extends StatefulWidget {
  const TwilioTestChatPage({
    super.key,
    required this.lead,
    this.pickImage = pickWebImage,
    this.pollInterval = const Duration(seconds: 6),
  });

  final TwilioTestLead lead;
  final ImagePicker pickImage;
  final Duration? pollInterval;

  @override
  State<TwilioTestChatPage> createState() => _TwilioTestChatPageState();
}

class _TwilioTestChatPageState extends State<TwilioTestChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  TwilioTestChat? _chat;
  bool _loading = true;
  bool _sending = false;
  bool _syncing = false;
  bool _sms = false;
  String? _loadError;
  String? _syncError;
  Timer? _poll;

  LeadRepository get _repo => context.read<LeadRepository>();
  String get _leadId => widget.lead.id;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _load();
    if (!mounted) return;
    await _sync();
    final interval = widget.pollInterval;
    if (mounted && interval != null) _poll = Timer.periodic(interval, (_) => _sync());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static String _message(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _load() async {
    try {
      final chat = await _repo.getTwilioTestChat(_leadId);
      if (!mounted) return;
      final grew = chat.messages.length != (_chat?.messages.length ?? 0);
      setState(() {
        _chat = chat;
        _loading = false;
        _loadError = null;
      });
      if (grew) _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _message(e);
      });
    }
  }

  /// Pulls receipts / replies from Twilio, then re-reads the conversation.
  Future<void> _sync() async {
    if (_syncing || !mounted) return;
    setState(() => _syncing = true);
    try {
      await _repo.syncTwilioTestChat(_leadId);
      if (mounted) setState(() => _syncError = null);
    } catch (e) {
      if (mounted) setState(() => _syncError = _message(e));
    }
    if (mounted) setState(() => _syncing = false);
    await _load();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _repo.sendTwilioTestText(_leadId, body: text, sms: _sms);
      _input.clear();
      await _load();
    } catch (e) {
      _snack(_message(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendTemplate() async {
    if (_sending) return;
    PickedImage? image;
    try {
      image = await widget.pickImage();
    } on ImagePickException catch (e) {
      _snack(e.message);
      return;
    }
    if (image == null || !mounted) return;
    final channel = await showDialog<String>(
      context: context,
      builder: (_) => _TemplateConfirmDialog(image: image!, lead: widget.lead),
    );
    if (channel == null) return;
    setState(() => _sending = true);
    try {
      await _repo.sendTwilioTestTemplate(_leadId, image: image.bytes, mimeType: image.mimeType, channel: channel);
      await _load();
    } catch (e) {
      _snack(_message(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retry(TwilioTestMessage m) async {
    try {
      await _repo.retryTwilioTestMessage(_leadId, m.id);
      await _load();
    } catch (e) {
      _snack(_message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final title = lead.businessName.isNotEmpty
        ? lead.businessName
        : lead.name.isNotEmpty
            ? lead.name
            : lead.phoneNumber;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 17)),
            Text(lead.phoneNumber, style: const TextStyle(fontSize: 12, color: AppTheme.faint)),
          ],
        ),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(onPressed: _sync, icon: const Icon(AppIcons.refresh, size: 18), tooltip: 'Check Twilio for replies'),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              children: [
                _buildBanner(),
                Expanded(child: _buildMessages()),
                _buildComposer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBanner() {
    final chat = _chat;
    if (chat == null) return const SizedBox.shrink();
    final String text;
    final Color color;
    if (chat.windowOpen) {
      final c = chat.windowClosesAt!.toLocal();
      text = 'WhatsApp free text is open until ${_time(c)} (the lead replied in the last 24 hours).';
      color = AppTheme.sage100;
    } else {
      text = 'WhatsApp free text is closed: the lead has not replied in the last 24 hours. '
          'Start with the template (image) or send an SMS.';
      color = AppTheme.accent100;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontSize: 12.5)),
          if (_syncError != null) ...[
            const SizedBox(height: 6),
            Text('Could not check Twilio: $_syncError', style: const TextStyle(fontSize: 12, color: AppTheme.danger)),
          ],
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final chat = _chat;
    if (chat == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError ?? 'Could not load the conversation.', style: const TextStyle(color: AppTheme.danger), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                icon: const Icon(AppIcons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (chat.messages.isEmpty) {
      return const Center(child: Text('No messages yet. Send one below.', style: TextStyle(color: AppTheme.faint)));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: chat.messages.length,
      itemBuilder: (context, i) {
        final m = chat.messages[i];
        return _Bubble(message: m, onRetry: m.isOutbound && m.hasFailed ? () => _retry(m) : null);
      },
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.neutral200))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('WhatsApp')),
                  ButtonSegment(value: true, label: Text('SMS')),
                ],
                selected: {_sms},
                onSelectionChanged: (v) => setState(() => _sms = v.first),
                showSelectedIcon: false,
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _sending ? null : _sendTemplate,
                icon: const Icon(AppIcons.plus, size: 18),
                label: const Text('Template + image'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendText(),
                  decoration: InputDecoration(
                    hintText: _sms ? 'Message to send by SMS' : 'Message to send on WhatsApp',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _sendText,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(AppIcons.chevronRight, size: 18),
                label: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _statusLabel(String status) => switch (status) {
      'sending' => 'Sending…',
      'sent' => 'Sent',
      'delivered' => 'Delivered',
      'read' => 'Read',
      'failed' => 'Failed',
      'undelivered' => 'Not delivered',
      _ => status,
    };

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.onRetry});

  final TwilioTestMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final out = m.isOutbound;
    final body = m.body.isNotEmpty
        ? m.body
        : m.isTemplate
            ? 'Outreach template'
            : (m.mediaName ?? m.type);
    final created = m.createdAt?.toLocal();
    final label = [
      m.isSms ? 'SMS' : 'WhatsApp',
      if (m.isTemplate) 'template + image',
      if (!m.isTemplate && m.body.isEmpty && m.mediaName != null) 'attachment',
    ].join(' · ');
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: out ? AppTheme.accent100 : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: m.hasFailed ? AppTheme.danger : AppTheme.neutral200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.faint)),
              const SizedBox(height: 4),
              SelectableText(body, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 6),
              Text(
                [
                  if (created != null) '${formatDate(created)} ${_time(created)}',
                  if (out) _statusLabel(m.status),
                ].join(' · '),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: m.hasFailed ? AppTheme.danger : (m.status == 'read' ? AppTheme.sage700 : AppTheme.faint),
                ),
              ),
              if (m.hasFailed) ...[
                const SizedBox(height: 4),
                Text(m.errorMessage ?? 'Twilio could not deliver this message.', style: const TextStyle(fontSize: 12, color: AppTheme.danger)),
                if (onRetry != null)
                  TextButton.icon(onPressed: onRetry, icon: const Icon(AppIcons.refresh, size: 16), label: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Last look before a real message goes out: shows the image and lets the
/// channel be chosen. Pops with `auto` / `whatsapp` / `sms`, or null on cancel.
class _TemplateConfirmDialog extends StatefulWidget {
  const _TemplateConfirmDialog({required this.image, required this.lead});

  final PickedImage image;
  final TwilioTestLead lead;

  @override
  State<_TemplateConfirmDialog> createState() => _TemplateConfirmDialogState();
}

class _TemplateConfirmDialogState extends State<_TemplateConfirmDialog> {
  String _channel = 'auto';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send the template?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This sends a real message to ${widget.lead.phoneNumber} with this image.'),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(widget.image.bytes, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'auto', label: Text('Auto')),
                ButtonSegment(value: 'whatsapp', label: Text('WhatsApp')),
                ButtonSegment(value: 'sms', label: Text('SMS')),
              ],
              selected: {_channel},
              onSelectionChanged: (v) => setState(() => _channel = v.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 6),
            Text(
              _channel == 'auto'
                  ? 'Auto: US (+1) numbers by SMS, every other country on WhatsApp.'
                  : _channel == 'sms'
                      ? 'SMS goes from the US Twilio number; many countries reject it.'
                      : 'WhatsApp marketing to US (+1) numbers is blocked by Meta.',
              style: const TextStyle(fontSize: 12, color: AppTheme.faint),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _channel), child: const Text('Send')),
      ],
    );
  }
}
