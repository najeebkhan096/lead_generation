import '../entities/lead.dart';

abstract class LeadRepository {
  Future<List<Lead>> searchLeads({
    required String location,
    required String category,
    required String dateRange,
    bool analyze = false,
    void Function(String message)? onProgress,
  });

  Future<List<Lead>> getCachedResults();

  Future<String> exportCsv();

  Future<String> exportJson();
}
