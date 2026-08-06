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
  static const String multiSearch = '/api/search/multi';
  static const String multiSearchStatus = '/api/search/multi/status';
  static const String multiSearchCancel = '/api/search/multi/cancel';
  static const String multiSearchCancelCategory = '/api/search/multi/cancel-category';
  static const String multiSearchPause = '/api/search/multi/pause';
  static const String multiSearchResume = '/api/search/multi/resume';
  static const String multiSearchPauseCategory = '/api/search/multi/pause-category';
  static const String multiSearchResumeCategory = '/api/search/multi/resume-category';
  static const String exportCsv = '/api/export/csv';
  static const String exportJson = '/api/export/json';
  static const String analyze = '/api/search/analyze';
  static const String saveToDb = '/api/db/save';
  static const String savedLeads = '/api/db/leads';
  static String leadWhatsAppStatus(String leadId) => '/api/db/leads/$leadId/whatsapp';
  static const String clearDb = '/api/db/clear';
  static const String checkWhatsApp = '/api/whatsapp/check';

  static const String whatsAppWebStatus = '/api/whatsapp-web/status';
  static const String whatsAppWebConnect = '/api/whatsapp-web/connect';
  static const String whatsAppWebDisconnect = '/api/whatsapp-web/disconnect';
  static const String whatsAppWebValidate = '/api/whatsapp-web/validate';
  static const String whatsAppWebValidateStatus = '/api/whatsapp-web/validate/status';
  static const String whatsAppWebValidateCancel = '/api/whatsapp-web/validate/cancel';
}
