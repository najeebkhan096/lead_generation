import '../../domain/entities/lead.dart';
import '../../domain/repositories/lead_repository.dart';
import '../datasources/lead_remote_datasource.dart';

class LeadRepositoryImpl implements LeadRepository {
  LeadRepositoryImpl(this._remote);

  final LeadRemoteDataSource _remote;

  @override
  Future<List<Lead>> searchLeads({
    required String location,
    required String category,
    required String dateRange,
    bool analyze = false,
  }) {
    return _remote.searchLeads(
      location: location,
      category: category,
      dateRange: dateRange,
      analyze: analyze,
    );
  }

  @override
  Future<List<Lead>> getCachedResults() => _remote.getResults();

  @override
  Future<String> exportCsv() => _remote.exportCsv();

  @override
  Future<String> exportJson() => _remote.exportJson();
}
