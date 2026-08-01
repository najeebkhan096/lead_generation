import '../../domain/entities/lead.dart';
import '../../domain/entities/search_progress.dart';
import '../../domain/entities/whatsapp_check_result.dart';
import '../../domain/repositories/lead_repository.dart';
import '../datasources/lead_remote_datasource.dart';

class LeadRepositoryImpl implements LeadRepository {
  LeadRepositoryImpl(this._remote);

  final LeadRemoteDataSource _remote;

  @override
  Future<List<Lead>> searchLeads({
    required String category,
    required String dateRange,
    String location = 'All US states',
    bool nationwide = true,
    int targetLeadCount = 100,
    bool analyze = false,
    void Function(SearchProgress progress, List<Lead> liveLeads)? onProgress,
  }) {
    return _remote.searchLeads(
      location: location,
      category: category,
      dateRange: dateRange,
      nationwide: nationwide,
      targetLeadCount: targetLeadCount,
      analyze: analyze,
      onProgress: onProgress,
    );
  }

  @override
  Future<List<Lead>> getCachedResults() => _remote.getResults();

  @override
  Future<Map<String, dynamic>?> getSearchSnapshot() => _remote.getSearchSnapshot();

  @override
  Future<List<Lead>> resumeSearch(
    Map<String, dynamic> snapshot, {
    void Function(SearchProgress progress, List<Lead> liveLeads)? onProgress,
  }) =>
      _remote.resumeSearch(snapshot, onProgress: onProgress);

  @override
  Future<String> exportCsv() => _remote.exportCsv();

  @override
  Future<String> exportJson() => _remote.exportJson();

  @override
  Future<String> saveToDatabase() => _remote.saveToDatabase();

  @override
  Future<List<Lead>> getSavedBusinesses() => _remote.getSavedLeads();

  @override
  Future<WhatsAppCheckResult> checkWhatsAppNumber(String phone) =>
      _remote.checkWhatsApp(phone);
}
