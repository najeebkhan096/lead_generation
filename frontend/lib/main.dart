import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/lead_remote_datasource.dart';
import 'data/repositories/lead_repository_impl.dart';
import 'domain/repositories/lead_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Real paths (/leads, /settings, …) instead of the default #/leads hash
  // URLs — Firebase Hosting's SPA rewrite (see firebase.json) already
  // sends every path to index.html, so this just needs the app to read
  // that path back out on load.
  usePathUrlStrategy();
  runApp(const LeadGenerationApp());
}

class LeadGenerationApp extends StatelessWidget {
  const LeadGenerationApp({super.key});

  @override
  Widget build(BuildContext context) {
    final remote = LeadRemoteDataSource();
    final repository = LeadRepositoryImpl(remote);

    return RepositoryProvider<LeadRepository>.value(
      value: repository,
      child: MaterialApp.router(
        title: 'LeadFinder',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: appRouter,
      ),
    );
  }
}
