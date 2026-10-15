import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../theme/app_theme.dart';
import '../utils/admin_analytics.dart';
import '../utils/date_format.dart';
import 'admin_widgets.dart';

/// One order in an admin list: client, owner, stage and payout at a glance.
///
/// Hide the line a screen already makes obvious — [showClient] is false on a
/// client's own page, [showSalesman] false on a salesman's.
class AdminSaleTile extends StatelessWidget {
  const AdminSaleTile({
    super.key,
    required this.sale,
    required this.onTap,
    this.showClient = true,
    this.showSalesman = true,
  });

  final Sale sale;
  final VoidCallback onTap;
  final bool showClient;
  final bool showSalesman;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final salesman = (sale.salesmanName ?? '').trim();
    final date = formatDate(sale.createdAt);
    final owner = salesman.isEmpty ? 'Unassigned' : salesman;
    // The title and subtitle are whatever the screen does not already say.
    final title = showClient ? sale.businessName : (date ?? 'Order');
    final subtitle = showClient
        ? [if (showSalesman) owner, ?date].join(' · ')
        : (showSalesman ? owner : null);
    final paid = sale.employeePaymentStatus == EmployeePaymentStatus.paid;

    return AdminCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(label: sale.status.label, tone: toneOfStatus(sale.status)),
              const SizedBox(height: 6),
              Text(
                sale.paymentsArchived
                    ? 'Earlier order'
                    : sale.employeePaymentAmount > 0
                        ? '${formatPkr(sale.employeePaymentAmount)} · ${paid ? 'Paid' : 'Due'}'
                        : 'No payout set',
                style: text.bodySmall?.copyWith(color: paid && !sale.paymentsArchived ? t.sageText : t.faint, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
