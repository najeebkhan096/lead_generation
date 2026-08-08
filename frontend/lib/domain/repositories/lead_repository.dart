import '../entities/lead.dart';
import '../entities/multi_search_snapshot.dart';
import '../entities/search_progress.dart';
import '../entities/whatsapp_check_result.dart';
import '../entities/whatsapp_web_status.dart';

abstract class LeadRepository {
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

  /// Records a manually-checked WhatsApp result for one lead — for
  /// checking by hand (e.g. on a phone) instead of the automated
  /// WhatsApp Web validation job. `leadId` must be [Lead.dbId].
  Future<void> markLeadWhatsAppStatus(String leadId, bool hasWhatsApp);

  /// Deletes a single saved lead from Firestore. Irreversible. `leadId`
  /// must be [Lead.dbId].
  Future<void> deleteLead(String leadId);

  /// Deletes every saved lead in an exact category. Irreversible. Returns
  /// how many were deleted.
  Future<int> deleteLeadsByCategory(String category);

  /// Deletes every lead and search record from Firestore. Irreversible.
  /// Does not touch Firebase Auth accounts.
  Future<String> clearAllData();

  Future<WhatsAppCheckResult> checkWhatsAppNumber(String phone);

  /// Starts a concurrent multi-category search — a worker pool where each
  /// (category, country) pair runs independently and picks up the next
  /// queued one as soon as it finishes, instead of running one at a time.
  ///
  /// [countries] with more than one entry runs every category against
  /// every country concurrently — "search this category in all countries."
  /// Omit it for the ordinary single-country multi-category search.
  Future<void> startMultiSearch({
    required List<String> categories,
    List<String>? countries,
    int concurrency = 4,
    String dateRange = '30',
    int maxResultsPerState = 150,
    int targetLeadCount = 100,
    bool analyze = false,
    String country = 'US',
  });

  /// Live dashboard snapshot for the current (or most recently finished)
  /// multi-category job.
  Future<MultiSearchSnapshot> getMultiSearchStatus();

  Future<void> cancelMultiSearchJob();

  /// [country] disambiguates which country's run of [category] to target —
  /// required when the job covers that category in more than one country.
  Future<void> cancelMultiSearchCategory(String category, {String? country});
  Future<void> pauseMultiSearchJob();
  Future<void> resumeMultiSearchJob();
  Future<void> pauseMultiSearchCategory(String category, {String? country});
  Future<void> resumeMultiSearchCategory(String category, {String? country});

  /// Live status of the backend's WhatsApp Web session — must show
  /// [WhatsAppWebConnectionStatus.ready] before validation can run.
  Future<WhatsAppWebStatus> getWhatsAppWebStatus();

  /// Starts (or resumes, if already linked) the WhatsApp Web session.
  /// Poll [getWhatsAppWebStatus] afterward for the QR code to scan.
  Future<void> connectWhatsAppWeb();

  Future<void> disconnectWhatsAppWeb();

  /// Runs a real WhatsApp Web check against each lead's phone number and
  /// flags `hasWhatsApp` on the ones confirmed registered. `leads` is
  /// `{id, phone, business}` per lead, where `id` is the Firestore [Lead.dbId].
  /// Capped server-side at 100 leads per run.
  Future<void> startWhatsAppValidation(List<Map<String, String>> leads);

  /// Automatically discovers and validates unchecked leads from Firestore.
  Future<void> startWhatsAppAutoValidation();

  Future<WhatsAppValidationSnapshot> getWhatsAppValidationStatus();

  Future<void> cancelWhatsAppValidation();
}
