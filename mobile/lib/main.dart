import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'pages/access_error_page.dart';
import 'pages/admin_navigation_page.dart';
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

/// The admin console lives in the web app; the phone app is for salesmen, so
/// an admin who signs in here lands in the same lead lists as everyone else.
/// The mobile console (lib/pages/admin_*.dart) is kept but only reachable in
/// a build made with `--dart-define=ADMIN_CONSOLE=true`; it needs a backend
/// the phone can reach (API_BASE_URL).
const bool kMobileAdminConsole = bool.fromEnvironment('ADMIN_CONSOLE');

class _ApprovedGate extends StatefulWidget {
  const _ApprovedGate();

  @override
  State<_ApprovedGate> createState() => _ApprovedGateState();
}

class _ApprovedGateState extends State<_ApprovedGate> {
  late final Future<({bool approved, bool isAdmin})> _check = _fetchStatus();

  Future<({bool approved, bool isAdmin})> _fetchStatus() async {
    final auth = AuthService();
    final approved = await auth.isCurrentUserApproved();
    final isAdmin = kMobileAdminConsole && await auth.isCurrentUserAdmin();
    return (approved: approved, isAdmin: isAdmin);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({bool approved, bool isAdmin})>(
      future: _check,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data;
        if (data?.approved == true) {
          if (data?.isAdmin == true) {
            return const AdminNavigationPage();
          }
          return const MainNavigationPage();
        }
        return const AccessErrorPage();
      },
    );
  }
}
