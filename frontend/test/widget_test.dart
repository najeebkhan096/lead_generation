import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/main.dart';

void main() {
  testWidgets('LeadFinder search page loads', (tester) async {
    await tester.pumpWidget(const LeadGenerationApp());
    expect(find.text('LeadFinder'), findsOneWidget);
    expect(find.text('Find 100 Leads Nationwide'), findsOneWidget);
  });
}
