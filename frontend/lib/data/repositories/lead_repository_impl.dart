import '../../domain/entities/lead.dart';
import '../../domain/entities/multi_search_snapshot.dart';
import '../../domain/entities/search_progress.dart';
import '../../domain/entities/whatsapp_check_result.dart';
import '../../domain/entities/whatsapp_web_status.dart';
import '../../domain/repositories/lead_repository.dart';
import '../datasources/lead_remote_datasource.dart';

class LeadRepositoryImpl implements LeadRepository {
  LeadRepositoryImpl(this._remote);

  final LeadRemoteDataSource _remote;

  @override
  Future<List<Lead>> searchLeads({
    String? category,
    List<String>? categories,
    required String dateRange,
    String location = 'All US states',
    bool nationwide = true,
    int targetLeadCount = 100,
    bool analyze = false,
    bool autoSave = true,
    String country = 'US',
    void Function(SearchProgress progress, List<Lead> liveLeads)? onProgress,
  }) {
    return _remote.searchLeads(
      location: location,
      category: category,
      categories: categories,
      dateRange: dateRange,
      nationwide: nationwide,
      targetLeadCount: targetLeadCount,
      analyze: analyze,
      autoSave: autoSave,
      country: country,
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
  Future<void> markLeadWhatsAppStatus(String leadId, bool hasWhatsApp) =>
      _remote.markLeadWhatsAppStatus(leadId, hasWhatsApp);

  @override
  Future<void> deleteLead(String leadId) => _remote.deleteLead(leadId);

  @override
  Future<int> deleteLeadsByCategory(String category) => _remote.deleteLeadsByCategory(category);

  @override
  Future<String> clearAllData() => _remote.clearAllData();

  @override
  Future<WhatsAppCheckResult> checkWhatsAppNumber(String phone) =>
      _remote.checkWhatsApp(phone);

  @override
  Future<void> startMultiSearch({
    required List<String> categories,
    List<String>? countries,
    int concurrency = 4,
    String dateRange = '30',
    int maxResultsPerState = 150,
    int targetLeadCount = 100,
    bool analyze = false,
    String country = 'US',
  }) =>
      _remote.startMultiSearch(
        categories: categories,
        countries: countries,
        concurrency: concurrency,
        dateRange: dateRange,
        maxResultsPerState: maxResultsPerState,
        targetLeadCount: targetLeadCount,
        analyze: analyze,
        country: country,
      );

  @override
  Future<MultiSearchSnapshot> getMultiSearchStatus() => _remote.getMultiSearchStatus();

  @override
  Future<void> cancelMultiSearchJob() => _remote.cancelMultiSearchJob();

  @override
  Future<void> cancelMultiSearchCategory(String category, {String? country}) =>
      _remote.cancelMultiSearchCategory(category, country: country);

  @override
  Future<void> pauseMultiSearchJob() => _remote.pauseMultiSearchJob();

  @override
  Future<void> resumeMultiSearchJob() => _remote.resumeMultiSearchJob();

  @override
  Future<void> pauseMultiSearchCategory(String category, {String? country}) =>
      _remote.pauseMultiSearchCategory(category, country: country);

  @override
  Future<void> resumeMultiSearchCategory(String category, {String? country}) =>
      _remote.resumeMultiSearchCategory(category, country: country);

  @override
  Future<WhatsAppWebStatus> getWhatsAppWebStatus() => _remote.getWhatsAppWebStatus();

  @override
  Future<void> connectWhatsAppWeb() => _remote.connectWhatsAppWeb();

  @override
  Future<void> disconnectWhatsAppWeb() => _remote.disconnectWhatsAppWeb();

  @override
  Future<void> startWhatsAppValidation(List<Map<String, String>> leads) =>
      _remote.startWhatsAppValidation(leads);

  @override
  Future<void> startWhatsAppAutoValidation() => _remote.startWhatsAppAutoValidation();

  @override
  Future<WhatsAppValidationSnapshot> getWhatsAppValidationStatus() =>
      _remote.getWhatsAppValidationStatus();

  @override
  Future<void> cancelWhatsAppValidation() => _remote.cancelWhatsAppValidation();
}
