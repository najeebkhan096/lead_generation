class ApiConstants {
  /// Backend base URL for local development.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3001',
  );

  static const String search = '/api/search';
  static const String results = '/api/search/results';
  static const String status = '/api/search/status';
  static const String exportCsv = '/api/export/csv';
  static const String exportJson = '/api/export/json';
  static const String analyze = '/api/search/analyze';
}
