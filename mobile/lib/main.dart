import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'pages/categories_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const LeadMobileApp());
}

class LeadMobileApp extends StatelessWidget {
  const LeadMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lead Outreach',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const CategoriesPage(),
    );
  }
}
