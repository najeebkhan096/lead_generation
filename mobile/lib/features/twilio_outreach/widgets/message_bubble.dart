import 'package:flutter/material.dart';
import '../models/outreach_message.dart';
import 'media_content.dart';
import 'status_ticks.dart';

String clockTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String dayLabel(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]}${t.year == n.year ? '' : ' ${t.year}'}';
}

class DateSeparator extends StatelessWidget {
  const DateSeparator(this.date, {super.key});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1F2C34) : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(dayLabel(date), style: TextStyle(fontSize: 12, color: dark ? Colors.white70 : Colors.black54)),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.quoted,
    this.firstInGroup = true,
    this.lastInGroup = true,
    required this.onLongPress,
    required this.onFailedTap,
    this.onQuoteTap,
  });

  final OutreachMessage message;
  final OutreachMessage? quoted;
  final bool firstInGroup; // top of a run of same-sender messages
  final bool lastInGroup; // bottom of the run (gets the tail corner)
  final VoidCallback onLongPress;
  final VoidCallback onFailedTap;
  final VoidCallback? onQuoteTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mine = message.isOutbound;
    final bg = mine
        ? (dark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
        : (dark ? const Color(0xFF1F2C34) : Colors.white);
    final fg = dark ? Colors.white : Colors.black87;
    const r = Radius.circular(12);
    const tail = Radius.circular(3);
    final radius = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: !mine && lastInGroup ? tail : r,
      bottomRight: mine && lastInGroup ? tail : r,
    );
    final hasMedia = message.media != null;
    final isTemplate = message.type == MessageType.template;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        onTap: message.hasFailed ? onFailedTap : null,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          margin: EdgeInsets.only(top: firstInGroup ? 6 : 1.5, bottom: 1.5, left: 8, right: 8),
          padding: EdgeInsets.fromLTRB(hasMedia ? 4 : 10, hasMedia ? 4 : 6, hasMedia ? 4 : 10, 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            border: message.hasFailed ? Border.all(color: Colors.red.shade300) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (quoted != null) _Quote(message: quoted!, mine: mine, onTap: onQuoteTap),
              if (isTemplate)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
                  child: Text('Outreach template', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.65))),
                ),
              if (hasMedia) MessageMedia(message: message),
              if (message.body.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(hasMedia ? 6 : 0, hasMedia ? 6 : 0, hasMedia ? 6 : 0, 0),
                  child: Text(message.body, style: TextStyle(color: fg, fontSize: 15)),
                ),
              Padding(
                padding: EdgeInsets.only(top: 2, right: hasMedia ? 4 : 0),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(clockTime(message.createdAt), style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.6))),
                  if (mine) ...[const SizedBox(width: 4), StatusTicks(message, size: 15)],
                ]),
              ),
              if (message.reactionEmojis.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: dark ? const Color(0xFF0B141A) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Text(message.reactionEmojis.join(' '), style: const TextStyle(fontSize: 14)),
                  ),
                ),
              if (message.hasFailed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                  child: Text('Not sent • tap for options',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.message, required this.mine, this.onTap});
  final OutreachMessage message;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: message.isOutbound ? const Color(0xFF128C7E) : Colors.purple, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message.isOutbound ? 'You' : 'Them', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          Text(message.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
        ]),
      ),
    );
  }
}
