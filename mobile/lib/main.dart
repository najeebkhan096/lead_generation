import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'pages/access_error_page.dart';
import 'pages/admin_navigation_page.dart';
import 'pages/login_page.dart';
import 'pages/main_navigation_page.dart';
import 'pages/pending_approval_page.dart';
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
  late Future<_Access> _check = _fetchStatus();

  Future<_Access> _fetchStatus() async {
    final access = await AuthService().loadAccess();
    return (
      approved: access.approved,
      isAdmin: kMobileAdminConsole && access.isAdmin,
      failed: access.failed,
    );
  }

  /// "Check again" on the waiting page. Only rebuilds the gate once the
  /// account is approved, so a still-waiting user is not bounced through a
  /// spinner.
  Future<bool> _recheck() async {
    final access = await _fetchStatus();
    if (mounted && access.approved) {
      setState(() {
        _check = Future.value(access);
      });
    }
    return access.approved;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Access>(
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
        // The check itself failing (offline, rules) is an error; a clean
        // "not approved" is the normal first-sign-in state.
        if (data == null || data.failed) return const AccessErrorPage();
        return PendingApprovalPage(onCheckAgain: _recheck);
      },
    );
  }
}

typedef _Access = ({bool approved, bool isAdmin, bool failed});
