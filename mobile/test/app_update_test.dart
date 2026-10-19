import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/pages/update_required_page.dart';
import 'package:lead_mobile/services/app_update.dart';
import 'package:lead_mobile/theme/app_theme.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('updateRequired', () {
    test('an install older than the minimum must update', () {
      expect(updateRequired(installedBuild: 1, minBuild: 2), isTrue);
    });

    test('the minimum build and anything newer may run', () {
      expect(updateRequired(installedBuild: 2, minBuild: 2), isFalse);
      expect(updateRequired(installedBuild: 3, minBuild: 2), isFalse);
    });
  });

  test('the rule reads its fields, with a sensible message when none is set', () {
    final rule = AppUpdateRule.fromData({'minBuild': 2, 'latestBuild': 3, 'apkUrl': ' https://x.example/app.apk ', 'message': ''});
    expect(rule.minBuild, 2);
    expect(rule.latestBuild, 3);
    expect(rule.apkUrl, 'https://x.example/app.apk');
    expect(rule.message, AppUpdateRule.defaultMessage);
  });

  testWidgets('the update page says which build is needed and offers the download, and cannot be dismissed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const UpdateRequiredPage(
        rule: AppUpdateRule(minBuild: 2, latestBuild: 2, apkUrl: 'https://x.example/app.apk', message: 'Please update.'),
        installedBuild: 1,
      ),
    ));

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Please update.'), findsOneWidget);
    expect(find.text('This is build 1. Build 2 is needed.'), findsOneWidget);
    expect(find.text('Download the update'), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
  });

  testWidgets('without a download link the page says so, and the button is off', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const UpdateRequiredPage(rule: AppUpdateRule(minBuild: 2, latestBuild: 2, apkUrl: '', message: 'x')),
    ));

    expect(find.textContaining('The download link is not set yet'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
}
