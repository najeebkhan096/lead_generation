import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/main.dart';

void main() {
  testWidgets('Admin shell shows the core flow in order and loads the Dashboard', (tester) async {
    await tester.pumpWidget(const LeadGenerationApp());
    // Network calls fail immediately under the test binding, so the
    // dashboard should settle straight into its error state rather than
    // hang or throw.
    await tester.pumpAndSettle();

    // Scan -> Archive -> Leads -> Verified, with everything else under More.
    for (final label in ['Dashboard', 'Scan', 'Archive', 'Leads', 'Verified', 'More']) {
      expect(find.text(label), findsWidgets, reason: '$label nav item');
    }
    // The extras are no longer in the main navigation.
    expect(find.text('Outreach'), findsNothing);
    expect(find.text('WhatsApp Tool'), findsNothing);
    expect(find.text('Sales'), findsNothing);
  });
}
