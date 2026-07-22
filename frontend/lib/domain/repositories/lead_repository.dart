import '../entities/lead.dart';

abstract class LeadRepository {
  Future<List<Lead>> searchLeads({
    required String location,
    required String category,
    required String dateRange,
    bool analyze = false,
  });

  Future<List<Lead>> getCachedResults();

  Future<String> exportCsv();

  Future<String> exportJson();
}
