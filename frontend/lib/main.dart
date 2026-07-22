import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'data/datasources/lead_remote_datasource.dart';
import 'data/repositories/lead_repository_impl.dart';
import 'presentation/bloc/search/search_bloc.dart';
import 'presentation/pages/search_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LeadGenerationApp());
}

class LeadGenerationApp extends StatelessWidget {
  const LeadGenerationApp({super.key});

  @override
  Widget build(BuildContext context) {
    final remote = LeadRemoteDataSource();
    final repository = LeadRepositoryImpl(remote);

    return RepositoryProvider.value(
      value: repository,
      child: BlocProvider(
        create: (_) => SearchBloc(repository),
        child: MaterialApp(
          title: 'LeadFinder',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const SearchPage(),
        ),
      ),
    );
  }
}
