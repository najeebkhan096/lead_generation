import 'dart:async';

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
import 'widgets/brand_splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    ThemeController.load(),
  ]);
  runApp(const LeadMobileApp());
}

class LeadMobileApp extends StatefulWidget {
  const LeadMobileApp({super.key});

  @override
  State<LeadMobileApp> createState() => _LeadMobileAppState();
}

class _LeadMobileAppState extends State<LeadMobileApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    // Signing out from anywhere (More, the admin console, the waiting page)
    // must land on the login screen. Screens opened on top of the home page
    // (More is one) would otherwise stay up over it, so the user would see
    // nothing happen. Close them all when the session ends.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Lead Outreach',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              final Widget page;
              if (snapshot.connectionState == ConnectionState.waiting) {
                page = const BrandSplash(key: ValueKey('splash'));
              } else if (snapshot.hasData) {
                // Keyed by account, so switching users never reuses the
                // previous user's access check.
                page = _ApprovedGate(key: ValueKey('gate-${snapshot.data!.uid}'));
              } else {
                page = const LoginPage(key: ValueKey('login'));
              }
              return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: page);
            },
          ),
        );
      },
    );
  }
}

/// Admins get the admin console on the phone too (`lib/pages/admin_*.dart`);
/// it reads from the backend (API_BASE_URL), which the phone must be able to
/// reach. Build with `--dart-define=ADMIN_CONSOLE=false` to send admins to the
/// salesman screens instead.
const bool kMobileAdminConsole = bool.fromEnvironment('ADMIN_CONSOLE', defaultValue: true);

class _ApprovedGate extends StatefulWidget {
  const _ApprovedGate({super.key});

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

  void _retry() {
    setState(() {
      _check = _fetchStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Access>(
      future: _check,
      builder: (context, snapshot) {
        final Widget page;
        final data = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          page = const BrandSplash(key: ValueKey('checking'), message: 'Checking your account…');
        } else if (data?.approved == true) {
          page = data?.isAdmin == true
              ? const AdminNavigationPage(key: ValueKey('admin'))
              : const MainNavigationPage(key: ValueKey('salesman'));
        } else if (data == null || data.failed) {
          // The check itself failing (offline, rules) is an error; a clean
          // "not approved" is the normal first-sign-in state.
          page = AccessErrorPage(key: const ValueKey('error'), onRetry: _retry);
        } else {
          page = PendingApprovalPage(key: const ValueKey('pending'), onCheckAgain: _recheck);
        }
        return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: page);
      },
    );
  }
}

typedef _Access = ({bool approved, bool isAdmin, bool failed});
