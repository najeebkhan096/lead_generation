import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/presentation/widgets/user_avatar.dart';

void main() {
  testWidgets('shows the initial when there is no photo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: UserAvatar(name: 'sara'))));
    expect(find.text('S'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows the initial, without throwing, when the photo fails to load (e.g. 429)', (tester) async {
    // The test HttpClient answers every request with 400, like Google's 429.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: UserAvatar(name: 'Sara', photoUrl: 'https://lh3.googleusercontent.com/a/x=s96-c')),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('S'), findsOneWidget);
  });
}
