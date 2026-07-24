import '../entities/lead.dart';

abstract class LeadRepository {
  Future<List<Lead>> searchLeads({
    required String category,
    required String dateRange,
    String location = 'All US states',
    bool nationwide = true,
    int targetLeadCount = 100,
    bool analyze = false,
    void Function(String message)? onProgress,
  });

  Future<List<Lead>> getCachedResults();

  Future<String> exportCsv();

  Future<String> exportJson();

  Future<String> saveToDatabase();
}
