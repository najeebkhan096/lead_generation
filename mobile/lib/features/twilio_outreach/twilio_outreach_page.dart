import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'pages/chat_page.dart';
import 'pages/lead_list_page.dart';
import 'services/outreach_api.dart';
import 'services/outreach_repository.dart';

/// The outreach screens use the app theme, so they look like the rest of the
/// app (indigo accent, flat bordered surfaces) in light and dark.
ThemeData outreachTheme(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppTheme.dark() : AppTheme.light();
}

/// Creates (or finds) the outreach lead for a business and opens its chat in
/// the in-app inbox. Throws [OutreachApiException] (e.g. INVALID_PHONE).
Future<void> openOutreachChat(
  BuildContext context, {
  required String name,
  required String businessName,
  required String phoneNumber,
  Map<String, String> details = const {},
}) async {
  final id = await OutreachApi().ensureLead(
    name: name,
    businessName: businessName,
    phoneNumber: phoneNumber,
    details: details,
  );
  final lead = await OutreachRepository()
      .watchLead(id)
      .firstWhere((l) => l != null);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Theme(
        data: outreachTheme(context),
        child: ChatPage(lead: lead!),
      ),
    ),
  );
}

/// WhatsApp outreach inbox. Leads, conversations and messages live in
/// Firestore (written by Cloud Functions from Twilio webhooks) and are read
/// through realtime streams. Runs in its own nested [Navigator] and [Theme] so
/// the WhatsApp look is kept and the app theme is untouched.
class TwilioOutreachPage extends StatelessWidget {
  const TwilioOutreachPage({super.key, this.embedded = false});

  /// True when shown as a bottom-bar tab: no back button, and back presses
  /// are left to the app instead of closing the whole page.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = outreachTheme(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final navigator = Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) =>
            LeadListPage(onExit: embedded ? null : rootNavigator.pop),
      ),
    );
    return Theme(
      data: theme,
      child: embedded
          ? navigator
          : NavigatorPopHandler(
              onPopWithResult: (_) => rootNavigator.maybePop(),
              child: navigator,
            ),
    );
  }
}
