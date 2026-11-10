import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'data/datasources/jobs_remote_datasource.dart';
import 'data/datasources/lead_remote_datasource.dart';
import 'data/repositories/jobs_repository_impl.dart';
import 'data/repositories/lead_repository_impl.dart';
import 'domain/repositories/jobs_repository.dart';
import 'domain/repositories/lead_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Real paths (/leads, /settings, …) instead of the default #/leads hash
  // URLs — Firebase Hosting's SPA rewrite (see firebase.json) already
  // sends every path to index.html, so this just needs the app to read
  // that path back out on load.
  usePathUrlStrategy();
  // Created before the first frame so the saved theme is already live.
  runApp(LeadGenerationApp(themeController: ThemeController()));
}

class LeadGenerationApp extends StatefulWidget {
  const LeadGenerationApp({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  State<LeadGenerationApp> createState() => _LeadGenerationAppState();
}

class _LeadGenerationAppState extends State<LeadGenerationApp> {
  // Created once: a theme switch re-runs every `build`, and the repositories
  // must survive it.
  late final LeadRepository _repository = LeadRepositoryImpl(LeadRemoteDataSource());

  // Jobs Finder has its own repository (and API client): it shares nothing with the lead flow.
  late final JobsRepository _jobsRepository = JobsRepositoryImpl(JobsRemoteDataSource());

  @override
  Widget build(BuildContext context) {
    final themeController = widget.themeController;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<LeadRepository>.value(value: _repository),
        RepositoryProvider<JobsRepository>.value(value: _jobsRepository),
      ],
      child: ThemeScope(
        controller: themeController,
        child: ListenableBuilder(
          listenable: themeController,
          builder: (context, _) => MaterialApp.router(
            title: 'LeadFinder',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeController.mode,
            routerConfig: appRouter,
          ),
        ),
      ),
    );
  }
}
