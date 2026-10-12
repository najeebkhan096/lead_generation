import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../utils/date_format.dart';

/// Human label for the backend's `emailSource` value — where on the
/// business's site the address was found.
String emailSourceLabel(String? source) {
  switch (source) {
    case 'contact_page':
      return 'Contact page';
    case 'about_page':
      return 'About page';
    case 'mailto':
      return 'Mailto link';
    case 'maps_listing':
      return 'Maps listing';
    case 'web_search':
      return 'Web search';
    case 'manual':
      return 'Added manually';
    case 'website':
      return 'Homepage';
    default:
      return 'Website';
  }
}

/// Copies [text] to the clipboard and confirms with a snackbar.
Future<void> copyToClipboard(BuildContext context, String text, String confirmation) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(confirmation)));
}

/// Compact summary card for one email lead — the email address leads the
/// card (it's the whole point of this lead type), with the business's
/// website/phone underneath. Tapping opens the full details page.
class EmailLeadCard extends StatelessWidget {
  const EmailLeadCard({
    super.key,
    required this.lead,
    required this.onTap,
    this.onDelete,
    this.deleting = false,
  });

  final Lead lead;
  final VoidCallback onTap;

  /// `null` hides the delete button.
  final VoidCallback? onDelete;

  /// Shows a spinner in place of the delete button while a delete request
  /// for this card is in flight.
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final addedOn = formatDate(lead.savedAt);
    final letter = lead.business.trim().isEmpty ? '?' : lead.business.trim()[0].toUpperCase();
    final warm = lead.business.hashCode.isEven;
    final email = lead.email;
    final extra = lead.emails.length > 1 ? lead.emails.length - 1 : 0;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: warm ? AppTheme.accent100 : AppTheme.sage100,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: warm ? AppTheme.accent700 : AppTheme.sage700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lead.business,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        _Chip(
                          label: lead.category,
                          background: AppTheme.accent100,
                          foreground: AppTheme.accent800,
                        ),
                      ],
                    ),
                  ),
                  if (onDelete != null)
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: deleting
                          ? const Padding(
                              padding: EdgeInsets.all(7),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: 'Delete',
                              onPressed: onDelete,
                              icon: const Icon(AppIcons.trash, size: 16, color: AppTheme.subtle),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (email != null)
                Container(
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.sage100,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: Row(
                    children: [
                      const Icon(AppIcons.mail, size: 15, color: AppTheme.sage700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: AppTheme.sage800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy email',
                        onPressed: () => copyToClipboard(context, email, 'Copied $email'),
                        icon: const Icon(AppIcons.copy, size: 15, color: AppTheme.sage700),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              if (lead.website != null && lead.website!.isNotEmpty)
                _InfoRow(icon: AppIcons.globe, text: _prettyUrl(lead.website!)),
              if (lead.phone != null && lead.phone!.isNotEmpty)
                _InfoRow(icon: AppIcons.phone, text: lead.phone!),
              if (lead.address != null && lead.address!.isNotEmpty)
                _InfoRow(icon: AppIcons.mapPin, text: lead.address!),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(
                          label: emailSourceLabel(lead.emailSource),
                          background: AppTheme.neutral100,
                          foreground: AppTheme.neutral700,
                        ),
                        if (extra > 0)
                          _Chip(
                            label: '+$extra more',
                            background: AppTheme.neutral100,
                            foreground: AppTheme.neutral700,
                          ),
                      ],
                    ),
                  ),
                  if (addedOn != null)
                    Text(addedOn, style: const TextStyle(fontSize: 11, color: AppTheme.faint)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "https://www.example.com/path/" → "example.com/path" — the card only has
/// room for a recognisable site name, the full URL is on the details page.
String _prettyUrl(String url) {
  return url
      .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')
      .replaceFirst(RegExp(r'/+$'), '');
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: AppTheme.faint),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.subtle),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.background, required this.foreground});

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
