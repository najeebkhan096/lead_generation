import 'package:flutter/material.dart';
import '../models/outreach_message.dart';
import '../services/outreach_api.dart';
import '../services/outreach_repository.dart';
import '../services/template_image.dart';

/// Sends a real message to any number (any country) so the SMS / WhatsApp
/// routing can be checked without opening a lead. Delivery status is shown live.
class SendTestPage extends StatefulWidget {
  const SendTestPage({super.key});

  @override
  State<SendTestPage> createState() => _SendTestPageState();
}

class _SendTestPageState extends State<SendTestPage> {
  final _api = OutreachApi();
  final _repo = OutreachRepository();
  final _phone = TextEditingController();
  final _text = TextEditingController(text: 'Test message from our outreach app.');

  /// `auto` = US (+1) numbers by SMS, everything else on WhatsApp.
  String _channel = 'auto';
  bool _busy = false;
  String? _error;
  String? _leadId;

  @override
  void dispose() {
    _phone.dispose();
    _text.dispose();
    super.dispose();
  }

  /// E.164 with the country code, e.g. +971501234567. Null when invalid.
  String? _normalizedPhone() {
    final p = _phone.text.replaceAll(RegExp(r'[\s\-().]'), '');
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(p) ? p : null;
  }

  Future<void> _run(Future<void> Function(String leadId, String messageId) send) async {
    final phone = _normalizedPhone();
    if (phone == null) {
      setState(() => _error = 'Enter the number with its country code, e.g. +971501234567.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final leadId = await _api.ensureLead(name: phone, businessName: '', phoneNumber: phone);
      await send(leadId, _repo.newMessageId(leadId));
      if (mounted) setState(() => _leadId = leadId);
    } on OutreachApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendSms() {
    final body = _text.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Type the message to send.');
      return Future.value();
    }
    return _run((leadId, id) => _api.sendSms(leadId: leadId, messageId: id, body: body));
  }

  Future<void> _sendTemplate() async {
    if (_normalizedPhone() == null) {
      setState(() => _error = 'Enter the number with its country code, e.g. +971501234567.');
      return;
    }
    String? url;
    try {
      url = await pickAndUploadTemplateImage(context, recipient: _phone.text.trim());
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not upload the image: $e');
      return;
    }
    if (url == null) return;
    await _run((leadId, id) => _api.sendTemplate(leadId: leadId, messageId: id, mediaUrl: url!, channel: _channel));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send a test message')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '+971501234567',
              helperText: 'Any country. Include the + and the country code.',
              border: OutlineInputBorder(),
            ),
          ),
          if (_normalizedPhone() case final p? when !p.startsWith('+1'))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Outside the US/Canada, SMS from a US number is usually rejected by Twilio. '
                'Use "Send template" with Auto or WhatsApp for this number.',
                style: TextStyle(fontSize: 12, color: Colors.deepOrange),
              ),
            ),
          const SizedBox(height: 16),
          const Text('Channel for the template', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Auto')),
              ButtonSegment(value: 'sms', label: Text('SMS')),
              ButtonSegment(value: 'whatsapp', label: Text('WhatsApp')),
            ],
            selected: {_channel},
            onSelectionChanged: (v) => setState(() => _channel = v.first),
          ),
          const SizedBox(height: 4),
          Text(
            _channel == 'auto'
                ? 'Auto: US (+1) numbers by SMS, every other country on WhatsApp.'
                : _channel == 'sms'
                    ? 'SMS works for any country your Twilio number can reach.'
                    : 'WhatsApp marketing to US (+1) numbers is blocked by Meta.',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'SMS text',
              helperText: 'Used by "Send SMS". A WhatsApp link is added at the end.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _sendSms,
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Send SMS'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _sendTemplate,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Send template'),
              ),
            ),
          ]),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_leadId != null) ...[
            const SizedBox(height: 24),
            const Text('Latest messages to this number', style: TextStyle(fontWeight: FontWeight.w600)),
            StreamBuilder<MessagePage>(
              stream: _repo.watchMessages(_leadId!, limit: 5),
              builder: (context, snap) {
                final msgs = (snap.data?.messages ?? const <OutreachMessage>[]).where((m) => m.isOutbound).toList();
                if (msgs.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: Text('Waiting…'));
                return Column(children: [for (final m in msgs) _ResultTile(m)]);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile(this.m);
  final OutreachMessage m;

  @override
  Widget build(BuildContext context) {
    final failed = m.hasFailed;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        failed ? Icons.error_outline : (m.status == MessageStatus.sending ? Icons.schedule : Icons.check_circle_outline),
        color: failed ? Colors.red : null,
      ),
      title: Text('${m.isSms ? 'SMS' : 'WhatsApp'} · ${m.status.name}'),
      subtitle: Text(
        failed ? (m.errorMessage ?? 'Failed') : (m.body.isEmpty ? m.preview : m.body),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
