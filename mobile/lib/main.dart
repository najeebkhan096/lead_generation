import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'pages/access_error_page.dart';
import 'pages/login_page.dart';
import 'pages/main_navigation_page.dart';
import 'services/auth_service.dart';
import 'services/theme_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    ThemeController.load(),
  ]);
  runApp(const LeadMobileApp());
}

class LeadMobileApp extends StatelessWidget {
  const LeadMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Lead Outreach',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasData) {
                return const _ApprovedGate();
              }
              return const LoginPage();
            },
          ),
        );
      },
    );
  }
}

/// After Firebase Auth succeeds, load `users/{uid}.approved`. Unapproved
/// accounts see a generic error — never an "awaiting approval" message.
class _ApprovedGate extends StatefulWidget {
  const _ApprovedGate();

  @override
  State<_ApprovedGate> createState() => _ApprovedGateState();
}

class _ApprovedGateState extends State<_ApprovedGate> {
  late final Future<bool> _approved = AuthService().isCurrentUserApproved();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _approved,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) {
          return const MainNavigationPage();
        }
        return const AccessErrorPage();
      },
    );
  }
}
