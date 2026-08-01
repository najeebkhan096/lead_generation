import 'package:flutter_test/flutter_test.dart';

import 'package:launcher/main.dart';

void main() {
  testWidgets('Home page shows Start Backend button', (WidgetTester tester) async {
    await tester.pumpWidget(const LauncherApp());
    await tester.pump();

    expect(find.text('Start Backend'), findsOneWidget);
  });
}
