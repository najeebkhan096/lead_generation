import 'package:flutter/material.dart';
import '../models/outreach_message.dart';
import '../../../theme/app_theme.dart';

/// Delivery indicator: spinner / ✓ / ✓✓ / blue ✓✓ / red !.
class StatusTicks extends StatelessWidget {
  const StatusTicks(this.message, {super.key, this.size = 16});

  final OutreachMessage message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (message.hasFailed) {
      return Icon(Icons.error, size: size, color: t.danger);
    }
    switch (message.status) {
      case MessageStatus.sending:
        return SizedBox(
          width: size - 4,
          height: size - 4,
          child: const CircularProgressIndicator(strokeWidth: 1.6),
        );
      case MessageStatus.sent:
        return Icon(Icons.check, size: size, color: t.faint);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: size, color: t.faint);
      case MessageStatus.read:
        return Icon(Icons.done_all, size: size, color: t.accent);
      case MessageStatus.failed:
      case MessageStatus.undelivered:
        return Icon(Icons.error, size: size, color: t.danger);
    }
  }
}
