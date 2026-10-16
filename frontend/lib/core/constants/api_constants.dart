class ApiConstants {
  /// Backend base URL.
  /// - Local Flutter run: defaults to http://localhost:3001
  /// - Production (served by Express): build with --dart-define=API_BASE_URL=
  ///   so requests use the same origin.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3001',
  );

  static const String mapsSessionStatus = '/api/maps-session/status';
  static const String mapsSessionLogin = '/api/maps-session/login';
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
  static const String dbCategories = '/api/db/categories';
  static const String dbOverview = '/api/db/overview';
  static String leadWhatsAppStatus(String leadId) => '/api/db/leads/$leadId/whatsapp';
  static String leadDelete(String leadId) => '/api/db/leads/$leadId';
  static const String websiteLeads = '/api/db/website-leads';
  static String websiteLeadDelete(String leadId) => '/api/db/website-leads/$leadId';
  static const String whatsappLeads = '/api/db/whatsapp-leads';
  static String whatsappLeadDelete(String leadId) => '/api/db/whatsapp-leads/$leadId';
  static const String emailLeads = '/api/db/email-leads';
  static String emailLeadDelete(String leadId) => '/api/db/email-leads/$leadId';
  static const String clearDb = '/api/db/clear';
  static const String checkWhatsApp = '/api/whatsapp/check';

  static const String whatsAppWebStatus = '/api/whatsapp-web/status';
  static const String whatsAppWebConnect = '/api/whatsapp-web/connect';
  static const String whatsAppWebDisconnect = '/api/whatsapp-web/disconnect';
  static const String whatsAppWebValidate = '/api/whatsapp-web/validate';
  static const String whatsAppWebValidateList = '/api/whatsapp-web/validate-list';
  static const String whatsAppWebValidateSaved = '/api/whatsapp-web/validate-saved';
  static const String whatsAppWebValidateAuto = '/api/whatsapp-web/validate-auto';
  static const String whatsAppWebUnvalidated = '/api/whatsapp-web/unvalidated';
  static const String whatsAppWebValidateStatus = '/api/whatsapp-web/validate/status';
  static const String whatsAppWebValidateCancel = '/api/whatsapp-web/validate/cancel';

  static const String watchlist = '/api/watchlist';
  static const String watchlistScan = '/api/watchlist/scan';
  static String watchlistDelete(String id) => '/api/watchlist/$id';
  static String watchlistAssign(String id) => '/api/watchlist/$id/assign';

  static const String users = '/api/users';
  static String userUpdate(String id) => '/api/users/$id';

  static const String excelArchives = '/api/excel-scans';
  static String excelArchiveData(String id) => '/api/excel-scans/$id/data';
  static String excelArchiveLeads(String id) => '/api/excel-scans/$id/leads';
  static String excelArchiveDelete(String id) => '/api/excel-scans/$id';
  static String excelArchiveResume(String id) => '/api/excel-scans/$id/resume';
  static String excelArchiveRescan(String id) => '/api/excel-scans/$id/rescan';

  static const String whatsappValidatedScans = '/api/whatsapp-validated-scans';
  static String whatsappValidatedData(String id) => '/api/whatsapp-validated-scans/$id/data';
  static String whatsappValidatedLeads(String id) => '/api/whatsapp-validated-scans/$id/leads';
  static String whatsappValidatedDelete(String id) => '/api/whatsapp-validated-scans/$id';

  static const String emailValidateList = '/api/email-validation/validate-list';
  static const String emailValidateSaved = '/api/email-validation/validate-saved';
  static const String emailValidateStatus = '/api/email-validation/status';
  static const String emailValidateCancel = '/api/email-validation/cancel';

  static const String emailValidatedScans = '/api/email-validated-scans';
  static String emailValidatedLeads(String id) => '/api/email-validated-scans/$id/leads';
  static String emailValidatedDelete(String id) => '/api/email-validated-scans/$id';

  static const String clients = '/api/clients';
  static String clientUpdate(String id) => '/api/clients/$id';
  static const String clientsScanReviews = '/api/clients/scan-reviews';
  static const String sales = '/api/sales';
  static const String salesStats = '/api/sales/stats';
  static const String salesScanReviews = '/api/sales/scan-reviews';
  static String saleUpdate(String id) => '/api/sales/$id';
  static String saleDelete(String id) => '/api/sales/$id';

  static const String twilioTestLeads = '/api/twilio-test/leads';
  static const String twilioInbox = '/api/twilio-test/inbox';
  static const String twilioInboxSync = '/api/twilio-test/inbox/sync';
  static String twilioTestLead(String id) => '/api/twilio-test/leads/$id';
  static String twilioTestChat(String id) => '/api/twilio-test/leads/$id/chat';
  static String twilioTestMessages(String id) => '/api/twilio-test/leads/$id/messages';
  static String twilioTestTemplate(String id) => '/api/twilio-test/leads/$id/template';
  static String twilioTestSync(String id) => '/api/twilio-test/leads/$id/sync';
  static String twilioTestRetry(String id, String messageId) =>
      '/api/twilio-test/leads/$id/messages/$messageId/retry';

  static const String outreachDashboard = '/api/outreach/dashboard';
  static const String outreachAnalytics = '/api/outreach/analytics';
  static const String outreachSettings = '/api/outreach/settings';
  static const String outreachRecords = '/api/outreach/records';
  static const String outreachCampaigns = '/api/outreach/campaigns';
  static const String outreachJob = '/api/outreach/job';
  static const String outreachJobCancel = '/api/outreach/job/cancel';
  static const String outreachRun = '/api/outreach/run';
  static const String outreachQueueDrain = '/api/outreach/queue/drain';
  static String outreachRecord(String id) => '/api/outreach/records/$id';
  static String outreachRecordDiscover(String id) => '/api/outreach/records/$id/discover-email';
  static String outreachRecordVerify(String id) => '/api/outreach/records/$id/verify-email';
  static String outreachRecordAnalyze(String id) => '/api/outreach/records/$id/analyze-website';
  static String outreachRecordGenerate(String id) => '/api/outreach/records/$id/generate-email';
  static String outreachRecordProcess(String id) => '/api/outreach/records/$id/process';
  static String outreachRecordApprove(String id) => '/api/outreach/records/$id/approve';
  static String outreachRecordReject(String id) => '/api/outreach/records/$id/reject';
  static String outreachRecordStatus(String id) => '/api/outreach/records/$id/status';
  static String outreachCampaign(String id) => '/api/outreach/campaigns/$id';
  static String outreachCampaignEnroll(String id) => '/api/outreach/campaigns/$id/enroll';
  static String outreachCampaignStart(String id) => '/api/outreach/campaigns/$id/start';
}
