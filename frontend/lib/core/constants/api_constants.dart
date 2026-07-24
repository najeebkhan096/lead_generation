class ApiConstants {
  /// Backend base URL.
  /// - Local Flutter run: defaults to http://localhost:3001
  /// - Production (served by Express): build with --dart-define=API_BASE_URL=
  ///   so requests use the same origin.
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
  static const String saveToDb = '/api/db/save';
  static const String savedLeads = '/api/db/leads';
}
