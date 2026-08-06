import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/main.dart';

void main() {
  testWidgets('Admin shell loads onto the Dashboard', (tester) async {
    await tester.pumpWidget(const LeadGenerationApp());
    // Network calls fail immediately under the test binding, so the
    // dashboard should settle straight into its error state rather than
    // hang or throw.
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Leads'), findsWidgets);
    expect(find.text('WhatsApp Tool'), findsOneWidget);
  });
}
