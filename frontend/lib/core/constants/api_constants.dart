class ApiConstants {
  /// Backend base URL.
  /// - Local Flutter run: defaults to http://localhost:3001
  /// - Production (served by Express): build with --dart-define=API_BASE_URL=
  ///   so requests use the same origin.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3001',
  );

  static const String stateScan = '/api/state-scan';
  static const String stateScanStatus = '/api/state-scan/status';
  static const String stateScanCancel = '/api/state-scan/cancel';
  static const String stateScanPause = '/api/state-scan/pause';
  static const String stateScanResume = '/api/state-scan/resume';

  static const String multiSearch = '/api/search/multi';
  static const String multiSearchStatus = '/api/search/multi/status';
  static const String multiSearchCancel = '/api/search/multi/cancel';
  static const String multiSearchCancelCategory = '/api/search/multi/cancel-category';
  static const String multiSearchPause = '/api/search/multi/pause';
  static const String multiSearchResume = '/api/search/multi/resume';
  static const String multiSearchPauseCategory = '/api/search/multi/pause-category';
  static const String multiSearchResumeCategory = '/api/search/multi/resume-category';
  static const String exportXlsxMulti = '/api/export/xlsx/multi';
  static const String savedLeads = '/api/db/leads';
  static String leadWhatsAppStatus(String leadId) => '/api/db/leads/$leadId/whatsapp';
  static String leadDelete(String leadId) => '/api/db/leads/$leadId';
  static const String websiteLeads = '/api/db/website-leads';
  static String websiteLeadDelete(String leadId) => '/api/db/website-leads/$leadId';
  static const String clearDb = '/api/db/clear';
  static const String checkWhatsApp = '/api/whatsapp/check';

  static const String whatsAppWebStatus = '/api/whatsapp-web/status';
  static const String whatsAppWebConnect = '/api/whatsapp-web/connect';
  static const String whatsAppWebDisconnect = '/api/whatsapp-web/disconnect';
  static const String whatsAppWebValidate = '/api/whatsapp-web/validate';
  static const String whatsAppWebValidateList = '/api/whatsapp-web/validate-list';
  static const String whatsAppWebValidateAuto = '/api/whatsapp-web/validate-auto';
  static const String whatsAppWebValidateStatus = '/api/whatsapp-web/validate/status';
  static const String whatsAppWebValidateCancel = '/api/whatsapp-web/validate/cancel';

  static const String watchlist = '/api/watchlist';
  static const String watchlistScan = '/api/watchlist/scan';
  static String watchlistDelete(String id) => '/api/watchlist/$id';
  static String watchlistAssign(String id) => '/api/watchlist/$id/assign';

  static const String users = '/api/users';

  static const String excelArchives = '/api/excel-scans';
  static String excelArchiveData(String id) => '/api/excel-scans/$id/data';
  static String excelArchiveLeads(String id) => '/api/excel-scans/$id/leads';
  static String excelArchiveDelete(String id) => '/api/excel-scans/$id';
  static String excelArchiveResume(String id) => '/api/excel-scans/$id/resume';

  static const String whatsappValidatedScans = '/api/whatsapp-validated-scans';
  static String whatsappValidatedData(String id) => '/api/whatsapp-validated-scans/$id/data';
  static String whatsappValidatedLeads(String id) => '/api/whatsapp-validated-scans/$id/leads';
  static String whatsappValidatedDelete(String id) => '/api/whatsapp-validated-scans/$id';

  static const String sales = '/api/sales';
  static const String salesStats = '/api/sales/stats';
  static String saleUpdate(String id) => '/api/sales/$id';
  static String saleDelete(String id) => '/api/sales/$id';
}
