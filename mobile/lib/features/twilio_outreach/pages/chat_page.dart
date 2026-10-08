import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/chat_controller.dart';
import '../models/outreach_lead.dart';
import '../models/outreach_message.dart';
import '../services/media_service.dart';
import '../services/outreach_api.dart';
import '../services/template_image.dart';
import '../widgets/composer.dart';
import '../widgets/message_bubble.dart';
import 'lead_info_page.dart';
import 'lead_picker.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.lead});
  final OutreachLead lead;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _c;
  final _scroll = ScrollController();
  bool _showJump = false;
  bool _sendingTemplate = false;

  @override
  void initState() {
    super.initState();
    _c = ChatController(leadId: widget.lead.id)..start();
    _c.addListener(_onChange);
    _scroll.addListener(() {
      final far = _scroll.hasClients && _scroll.offset > 400;
      if (far != _showJump) setState(() => _showJump = far);
      // The list is reversed: its "end" is the oldest loaded message.
      if (_scroll.hasClients && _scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        _c.loadOlder();
      }
    });
  }

  void _onChange() {
    final err = _c.lastActionError;
    if (err != null) {
      _c.lastActionError = null;
      _snack(err);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _jumpToBottom() => _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  Future<void> _sendTemplate() async {
    if (_sendingTemplate) return;
    setState(() => _sendingTemplate = true);
    try {
      final url = await pickAndUploadTemplateImage(context);
      if (url == null) return;
      _c.sendTemplate(url);
    } catch (e) {
      _snack('Could not upload the image: $e');
    } finally {
      if (mounted) setState(() => _sendingTemplate = false);
    }
  }

  // ---- message actions -------------------------------------------------------

  Future<void> _showActions(OutreachMessage m) async {
    final canReply = !m.isLocalOnly && _c.windowOpen;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!m.isLocalOnly) _reactionRow(ctx, m),
          if (canReply) _tile(ctx, Icons.reply, 'Reply', 'reply'),
          if (m.body.isNotEmpty) _tile(ctx, Icons.copy, 'Copy text', 'copy'),
          if (m.media?.storagePath != null) _tile(ctx, Icons.download_outlined, 'Save / share file', 'share'),
          if (!m.isLocalOnly && m.type != MessageType.template) _tile(ctx, Icons.forward, 'Forward', 'forward'),
          if (m.hasFailed) _tile(ctx, Icons.refresh, 'Retry', 'retry'),
          if (!m.isLocalOnly) _tile(ctx, Icons.info_outline, 'Message info', 'info'),
          _tile(ctx, Icons.delete_outline, m.isLocalOnly ? 'Discard' : 'Delete for me', 'delete'),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'reply':
        _c.setReply(m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.body));
        _snack('Copied');
      case 'share':
        await _shareFile(m);
      case 'forward':
        await _forward(m);
      case 'retry':
        await _c.retry(m);
      case 'info':
        await _showInfo(m);
      case 'delete':
        await _confirmDelete(m);
    }
  }

  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  Widget _reactionRow(BuildContext ctx, OutreachMessage m) {
    final mine = m.reactions[_c.myUid];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        for (final e in _quickReactions)
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              Navigator.pop(ctx);
              _c.react(m, e);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: mine == e ? Colors.black12 : null,
              ),
              child: Text(e, style: const TextStyle(fontSize: 26)),
            ),
          ),
      ]),
    );
  }

  Future<void> _shareFile(OutreachMessage m) async {
    final media = m.media;
    if (media == null) return;
    _snack('Preparing ${media.fileName}…');
    try {
      await MediaExport.share(media);
    } on MediaValidationException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not download the file: $e');
    }
  }

  Widget _tile(BuildContext ctx, IconData i, String t, String v) =>
      ListTile(leading: Icon(i), title: Text(t), onTap: () => Navigator.pop(ctx, v));

  Future<void> _confirmDelete(OutreachMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text(m.isLocalOnly
            ? 'This unsent message will be discarded.'
            : 'It is removed from your inbox only. WhatsApp cannot recall a message that was already sent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _c.hide(m);
      } catch (e) {
        _snack('Could not delete: $e');
      }
    }
  }

  Future<void> _forward(OutreachMessage m) async {
    final target = await pickLead(context, excludeId: widget.lead.id);
    if (target == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Forwarding to ${target.name}…')));
    final tmp = ChatController(leadId: target.id);
    try {
      await tmp.forwardHere(m);
      final err = await tmp.settle();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(err ?? 'Forwarded to ${target.name}')));
    } on MediaValidationException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Forward failed: $e')));
    } finally {
      tmp.dispose();
    }
  }

  Future<void> _showInfo(OutreachMessage m) async {
    String t(DateTime? d) => d == null ? '—' : '${dayLabel(d)} ${clockTime(d)}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Message info'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row('Status', m.status.name),
            if (m.isOutbound) ...[
              _row('Sent', t(m.sentAt)),
              _row('Delivered', t(m.deliveredAt)),
              _row('Read', t(m.readAt)),
            ] else
              _row('Received', t(m.createdAt)),
            if (m.failedAt != null) _row('Failed', t(m.failedAt)),
            if (m.errorCode != null) _row('Error code', '${m.errorCode}'),
            if (m.errorMessage != null) _row('Error', m.errorMessage!),
            if (m.twilioSid != null) _row('Twilio SID', m.twilioSid!),
            const SizedBox(height: 8),
            const Text('Read receipts only appear if the recipient has them enabled in WhatsApp.',
                style: TextStyle(fontSize: 11)),
          ]),
        ),
        actions: [
          if (m.isOutbound && m.twilioSid != null && m.status != MessageStatus.read)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _c.refreshStatus(m);
                  _snack('Status refreshed');
                } on OutreachApiException catch (e) {
                  _snack(e.message);
                }
              },
              child: const Text('Refresh status'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 92, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: SelectableText(v)),
        ]),
      );

  Future<void> _onFailedTap(OutreachMessage m) async {
    final reason = m.localError ?? m.errorMessage ?? 'The message could not be sent.';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.error, color: Colors.red.shade400),
              const SizedBox(width: 8),
              const Text('Message not sent', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 8),
            Text(reason),
            if (m.errorCode != null) Text('Code ${m.errorCode}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text(m.isLocalOnly ? 'Discard' : 'Delete'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'retry'), icon: const Icon(Icons.refresh), label: const Text('Retry'))),
            ]),
          ]),
        ),
      ),
    );
    if (action == 'retry') await _c.retry(m);
    if (action == 'delete') await _c.hide(m);
  }

  // ---- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lead = _c.lead ?? widget.lead;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B141A) : const Color(0xFFEFEAE2),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(
            backgroundColor: Colors.white24,
            child: Text(lead.initial, style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeadInfoPage(lead: lead))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(lead.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
                  Text(lead.phoneNumber,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ]),
              ),
            ),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'Send template',
            icon: _sendingTemplate
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.campaign_outlined),
            onPressed: _sendingTemplate ? null : _sendTemplate,
          ),
        ],
      ),
      body: Column(children: [
        Expanded(child: _buildList(dark)),
        _buildBottom(),
      ]),
    );
  }

  Widget _buildBottom() {
    final open = _c.windowOpen;
    final left = open ? _c.conversation.remaining() : null;
    final never = _c.conversation.lastInboundAt == null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (open && left != null && left < const Duration(hours: 2))
        Container(
          width: double.infinity,
          color: Colors.amber.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text('Free-form replies close in ${left.inMinutes} min (24-hour WhatsApp window).',
              style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ),
      if (!open)
        Material(
          color: dark ? const Color(0xFF1F2C34) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
            child: Row(children: [
              const Icon(Icons.lock_clock, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  never
                      ? 'No reply yet: WhatsApp only delivers an approved template first.'
                      : 'Over 24 h since their last message: only a template can be sent until they reply.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: _sendingTemplate ? null : _sendTemplate,
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: const Text('Template'),
              ),
            ]),
          ),
        ),
      ChatComposer(controller: _c),
    ]);
  }

  Widget _buildList(bool dark) {
    if (_c.loading) return const Center(child: CircularProgressIndicator());
    if (_c.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 8),
            const Text("Couldn't load this conversation.", textAlign: TextAlign.center),
            Text('${_c.error}', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
          ]),
        ),
      );
    }
    final items = _c.items;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: dark ? Colors.white30 : Colors.black26),
            const SizedBox(height: 12),
            const Text('No messages yet', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Start with the outreach template (top-right). After they reply you can chat freely for 24 hours.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
          ]),
        ),
      );
    }

    // `items` is newest-first (list is reversed): index+1 is the OLDER neighbour.
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final m = items[i];
      final older = i + 1 < items.length ? items[i + 1] : null;
      final newer = i > 0 ? items[i - 1] : null;
      bool sameRun(OutreachMessage a, OutreachMessage b) =>
          a.direction == b.direction && a.createdAt.difference(b.createdAt).abs() < const Duration(minutes: 5) && _sameDay(a.createdAt, b.createdAt);
      rows.add(MessageBubble(
        key: ValueKey(m.id),
        message: m,
        quoted: _c.messageById(m.replyToMessageId),
        firstInGroup: older == null || !sameRun(m, older),
        lastInGroup: newer == null || !sameRun(m, newer),
        onLongPress: () => _showActions(m),
        onFailedTap: () => _onFailedTap(m),
      ));
      if (older == null || !_sameDay(m.createdAt, older.createdAt)) rows.add(DateSeparator(m.createdAt));
    }

    return Stack(children: [
      ListView(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ...rows,
          if (_c.loadingOlder)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      if (_showJump)
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'jump_bottom',
            onPressed: _jumpToBottom,
            child: const Icon(Icons.keyboard_arrow_down),
          ),
        ),
    ]);
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

