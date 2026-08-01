import '../entities/lead.dart';
import '../entities/search_progress.dart';
import '../entities/whatsapp_check_result.dart';

abstract class LeadRepository {
  Future<List<Lead>> searchLeads({
    required String category,
    required String dateRange,
    String location = 'All US states',
    bool nationwide = true,
    int targetLeadCount = 100,
    bool analyze = false,
    void Function(SearchProgress progress, List<Lead> liveLeads)? onProgress,
  });

  Future<List<Lead>> getCachedResults();

  /// Server-side search snapshot, or `null` if nothing is running/finished.
  Future<Map<String, dynamic>?> getSearchSnapshot();

  Future<List<Lead>> resumeSearch(
    Map<String, dynamic> snapshot, {
    void Function(SearchProgress progress, List<Lead> liveLeads)? onProgress,
  });

  Future<String> exportCsv();

  Future<String> exportJson();

  Future<String> saveToDatabase();

  Future<List<Lead>> getSavedBusinesses();

  Future<WhatsAppCheckResult> checkWhatsAppNumber(String phone);
}
