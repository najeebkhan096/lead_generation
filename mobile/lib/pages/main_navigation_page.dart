import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'profile_page.dart';
import 'verified_leads_page.dart';

/// The whole app is one screen with two tabs — the leads each validator
/// confirmed, each from its own collection:
///
///   WhatsApp  |  Email
///
/// The account button (top right) opens "More": outreach chat, sales,
/// settings and Sign out. Unvalidated leads (scans, 1-star, no website) are
/// not shown on the phone; validate them in the web console and they appear
/// here after a pull-to-refresh.
class MainNavigationPage extends StatelessWidget {
  const MainNavigationPage({super.key});

  void _openMore(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        // ProfilePage draws its own "More" header; the bar only gives the
        // back arrow.
        builder: (_) => Scaffold(appBar: AppBar(), body: const ProfilePage()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: t.surface,
                          borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusPill)),
                        ),
                        child: TabBar(
                          indicator: BoxDecoration(
                            color: t.accent,
                            borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusPill)),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          labelColor: t.onFill,
                          unselectedLabelColor: t.subtle,
                          splashBorderRadius: BorderRadius.circular(AppTheme.radiusPill),
                          tabs: const [
                            Tab(height: 40, icon: Icon(AppIcons.chat, size: 18), iconMargin: EdgeInsets.zero, text: 'WhatsApp'),
                            Tab(height: 40, icon: Icon(AppIcons.mail, size: 18), iconMargin: EdgeInsets.zero, text: 'Email'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'More',
                      onPressed: () => _openMore(context),
                      icon: const Icon(AppIcons.user),
                      color: t.subtle,
                    ),
                  ],
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _KeepAlive(child: VerifiedLeadsPage(kind: VerifiedKind.whatsapp)),
                    _KeepAlive(child: VerifiedLeadsPage(kind: VerifiedKind.email)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps a tab's list (scroll position, loaded pages) when you switch tabs
/// instead of reloading it from page one.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
