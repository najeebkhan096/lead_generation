import 'dart:typed_data';

import '../entities/lead.dart';
import '../entities/multi_search_snapshot.dart';
import '../entities/excel_archive.dart';
import '../entities/sale.dart';
import '../entities/sales_user.dart';
import '../entities/watchlist_entry.dart';
import '../entities/whatsapp_check_result.dart';
import '../entities/whatsapp_web_status.dart';

abstract class LeadRepository {
  /// The most recent multi-category (and/or multi-country) scan as one
  /// .xlsx workbook with one sheet per category.
  Future<Uint8List> exportMultiExcel();

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
  /// [exportOnly] skips per-lead Firestore writes entirely — leads are
  /// packaged into one .xlsx workbook *per category* (one sheet per
  /// country), each uploaded to Firebase Storage the instant that category
  /// finishes across every selected country, independently of every other
  /// category. See [MultiSearchSnapshot.categoryArchives].
  Future<void> startMultiSearch({
    required List<String> categories,
    List<String>? countries,
    int concurrency = 4,
    String dateRange = '30',
    int maxResultsPerState = 150,
    int targetLeadCount = 100,
    bool analyze = false,
    bool exportOnly = false,
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

  /// Same as [startWhatsAppValidation] but for leads that were never saved
  /// to Firestore (e.g. extracted from an Excel archive) — results are
  /// read back from [getWhatsAppValidationStatus] and correlated by the
  /// `id` each lead was sent with, not written to any document.
  Future<void> validateExternalLeads(List<Map<String, String>> leads);

  /// Automatically discovers and validates unchecked leads from Firestore.
  Future<void> startWhatsAppAutoValidation();

  Future<WhatsAppValidationSnapshot> getWhatsAppValidationStatus();

  Future<void> cancelWhatsAppValidation();

  /// Adds a business URL to the manually-curated watchlist (idempotent per
  /// URL server-side — adding the same URL twice returns the existing entry).
  Future<WatchlistEntry> addWatchlistEntry({
    required String url,
    String? name,
    String country = 'US',
    String? assignedTo,
    String? assignedToName,
  });

  Future<List<WatchlistEntry>> listWatchlist();

  /// Removes a business from the watchlist. Irreversible.
  Future<void> deleteWatchlistEntry(String id);

  /// Reassigns (or clears, passing both null) which salesman a watchlist
  /// entry is assigned to.
  Future<WatchlistEntry> assignWatchlistEntry(
    String id, {
    String? assignedTo,
    String? assignedToName,
  });

  /// Salesmen (mobile app users) available to assign watchlist businesses to.
  Future<List<SalesUser>> listSalesmen();

  /// Re-scans every watchlisted business now and returns which ones picked
  /// up new reviews since the last scan.
  /// [dateRange] (days, e.g. '30'/'45'/'60') bounds how far back a review
  /// can be and still count as "new" — older reviews are ignored entirely.
  Future<List<WatchlistScanResult>> scanWatchlist({String dateRange = '30'});

  /// Every Excel-archived scan (see `exportOnly` on [startMultiSearch]),
  /// newest first.
  Future<List<ExcelArchive>> listExcelArchives();

  /// Reads one archive's workbook back into JSON for display — one entry
  /// per worksheet (category).
  Future<List<ExcelArchiveSheet>> getExcelArchiveData(String id);

  /// Deletes an archive from Storage and its Firestore metadata. Irreversible.
  Future<void> deleteExcelArchive(String id);

  /// Picks a stranded `status: 'partial'` archive back up — see
  /// [LeadRemoteDataSource.resumeExcelArchive]. Starts a real scan job;
  /// poll [getMultiSearchStatus] afterward same as [startMultiSearch].
  Future<void> resumeExcelArchive(String id);

  /// Extracts every business in an archive as [Lead]s for display — these
  /// were never saved to Firestore, so [Lead.dbId] is always null.
  Future<List<Lead>> getExcelArchiveLeads(String id);

  /// Uploads WhatsApp-validated leads (one sheet per category) as a new
  /// .xlsx archive in the separate `whatsappValidatedScans` collection.
  Future<ExcelArchive> uploadValidatedArchive({
    required List<Map<String, dynamic>> sheets,
    String? sourceArchiveId,
    String? sourceFileName,
    List<String>? countries,
  });

  Future<List<ExcelArchive>> listValidatedArchives();

  Future<List<ExcelArchiveSheet>> getValidatedArchiveData(String id);

  Future<List<Lead>> getValidatedArchiveLeads(String id);

  Future<void> deleteValidatedArchive(String id);

  Future<Sale> createSale({
    required String businessName,
    String? reviewLink,
    String? salesmanId,
    String? salesmanName,
    LeadStatus leadStatus = LeadStatus.newLead,
    double priceChargedToClient = 0,
    ClientPaymentStatus clientPaymentStatus = ClientPaymentStatus.pending,
    String? clientPaymentMethod,
    double employeePaymentAmount = 0,
    EmployeePaymentStatus employeePaymentStatus = EmployeePaymentStatus.pending,
    double clientAmountReceived = 0,
    double removalCost = 0,
  });

  /// [salesmanId] filters to one salesman's sales; omit for everyone's.
  Future<List<Sale>> listSales({String? salesmanId});

  Future<Sale> updateSale(
    String id, {
    String? businessName,
    String? reviewLink,
    String? salesmanId,
    String? salesmanName,
    LeadStatus? leadStatus,
    double? priceChargedToClient,
    ClientPaymentStatus? clientPaymentStatus,
    String? clientPaymentMethod,
    double? employeePaymentAmount,
    EmployeePaymentStatus? employeePaymentStatus,
    double? clientAmountReceived,
    double? removalCost,
  });

  Future<void> deleteSale(String id);

  /// [salesmanId] scopes the dashboard to one salesman; omit for the
  /// full-team rollup.
  Future<SalesStats> getSalesStats({String? salesmanId});
}
