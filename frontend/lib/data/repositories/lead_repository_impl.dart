import 'dart:typed_data';

import '../../domain/entities/lead.dart';
import '../../domain/entities/multi_search_snapshot.dart';
import '../../domain/entities/search_progress.dart';
import '../../domain/entities/excel_archive.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sales_user.dart';
import '../../domain/entities/watchlist_entry.dart';
import '../../domain/entities/whatsapp_check_result.dart';
import '../../domain/entities/whatsapp_web_status.dart';
import '../../domain/repositories/lead_repository.dart';
import '../datasources/lead_remote_datasource.dart';

class LeadRepositoryImpl implements LeadRepository {
  LeadRepositoryImpl(this._remote);

  final LeadRemoteDataSource _remote;

  @override
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
  }) {
    return _remote.searchLeads(
      location: location,
      category: category,
      categories: categories,
      dateRange: dateRange,
      nationwide: nationwide,
      targetLeadCount: targetLeadCount,
      analyze: analyze,
      autoSave: autoSave,
      country: country,
      onProgress: onProgress,
    );
  }

  @override
  Future<List<Lead>> getCachedResults() => _remote.getResults();

  @override
  Future<Map<String, dynamic>?> getSearchSnapshot() => _remote.getSearchSnapshot();

  @override
  Future<List<Lead>> resumeSearch(
    Map<String, dynamic> snapshot, {
    void Function(SearchProgress progress, List<Lead> liveLeads)? onProgress,
  }) =>
      _remote.resumeSearch(snapshot, onProgress: onProgress);

  @override
  Future<String> exportCsv() => _remote.exportCsv();

  @override
  Future<String> exportJson() => _remote.exportJson();

  @override
  Future<Uint8List> exportExcel() => _remote.exportExcel();

  @override
  Future<Uint8List> exportMultiExcel() => _remote.exportMultiExcel();

  @override
  Future<String> saveToDatabase() => _remote.saveToDatabase();

  @override
  Future<List<Lead>> getSavedBusinesses() => _remote.getSavedLeads();

  @override
  Future<void> markLeadWhatsAppStatus(String leadId, bool hasWhatsApp) =>
      _remote.markLeadWhatsAppStatus(leadId, hasWhatsApp);

  @override
  Future<void> deleteLead(String leadId) => _remote.deleteLead(leadId);

  @override
  Future<int> deleteLeadsByCategory(String category) => _remote.deleteLeadsByCategory(category);

  @override
  Future<String> clearAllData() => _remote.clearAllData();

  @override
  Future<WhatsAppCheckResult> checkWhatsAppNumber(String phone) =>
      _remote.checkWhatsApp(phone);

  @override
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
  }) =>
      _remote.startMultiSearch(
        categories: categories,
        countries: countries,
        concurrency: concurrency,
        dateRange: dateRange,
        maxResultsPerState: maxResultsPerState,
        targetLeadCount: targetLeadCount,
        analyze: analyze,
        exportOnly: exportOnly,
        country: country,
      );

  @override
  Future<MultiSearchSnapshot> getMultiSearchStatus() => _remote.getMultiSearchStatus();

  @override
  Future<void> cancelMultiSearchJob() => _remote.cancelMultiSearchJob();

  @override
  Future<void> cancelMultiSearchCategory(String category, {String? country}) =>
      _remote.cancelMultiSearchCategory(category, country: country);

  @override
  Future<void> pauseMultiSearchJob() => _remote.pauseMultiSearchJob();

  @override
  Future<void> resumeMultiSearchJob() => _remote.resumeMultiSearchJob();

  @override
  Future<void> pauseMultiSearchCategory(String category, {String? country}) =>
      _remote.pauseMultiSearchCategory(category, country: country);

  @override
  Future<void> resumeMultiSearchCategory(String category, {String? country}) =>
      _remote.resumeMultiSearchCategory(category, country: country);

  @override
  Future<WhatsAppWebStatus> getWhatsAppWebStatus() => _remote.getWhatsAppWebStatus();

  @override
  Future<void> connectWhatsAppWeb() => _remote.connectWhatsAppWeb();

  @override
  Future<void> disconnectWhatsAppWeb() => _remote.disconnectWhatsAppWeb();

  @override
  Future<void> startWhatsAppValidation(List<Map<String, String>> leads) =>
      _remote.startWhatsAppValidation(leads);

  @override
  Future<void> validateExternalLeads(List<Map<String, String>> leads) =>
      _remote.validateExternalLeads(leads);

  @override
  Future<void> startWhatsAppAutoValidation() => _remote.startWhatsAppAutoValidation();

  @override
  Future<WhatsAppValidationSnapshot> getWhatsAppValidationStatus() =>
      _remote.getWhatsAppValidationStatus();

  @override
  Future<void> cancelWhatsAppValidation() => _remote.cancelWhatsAppValidation();

  @override
  Future<WatchlistEntry> addWatchlistEntry({
    required String url,
    String? name,
    String country = 'US',
    String? assignedTo,
    String? assignedToName,
  }) =>
      _remote.addWatchlistEntry(
        url: url,
        name: name,
        country: country,
        assignedTo: assignedTo,
        assignedToName: assignedToName,
      );

  @override
  Future<List<WatchlistEntry>> listWatchlist() => _remote.listWatchlist();

  @override
  Future<void> deleteWatchlistEntry(String id) => _remote.deleteWatchlistEntry(id);

  @override
  Future<WatchlistEntry> assignWatchlistEntry(
    String id, {
    String? assignedTo,
    String? assignedToName,
  }) =>
      _remote.assignWatchlistEntry(id, assignedTo: assignedTo, assignedToName: assignedToName);

  @override
  Future<List<SalesUser>> listSalesmen() => _remote.listSalesmen();

  @override
  Future<List<WatchlistScanResult>> scanWatchlist({String dateRange = '30'}) =>
      _remote.scanWatchlist(dateRange: dateRange);

  @override
  Future<List<ExcelArchive>> listExcelArchives() => _remote.listExcelArchives();

  @override
  Future<List<ExcelArchiveSheet>> getExcelArchiveData(String id) => _remote.getExcelArchiveData(id);

  @override
  Future<void> deleteExcelArchive(String id) => _remote.deleteExcelArchive(id);

  @override
  Future<List<Lead>> getExcelArchiveLeads(String id) => _remote.getExcelArchiveLeads(id);

  @override
  Future<ExcelArchive> uploadValidatedArchive({
    required List<Map<String, dynamic>> sheets,
    String? sourceArchiveId,
    String? sourceFileName,
    List<String>? countries,
  }) =>
      _remote.uploadValidatedArchive(
        sheets: sheets,
        sourceArchiveId: sourceArchiveId,
        sourceFileName: sourceFileName,
        countries: countries,
      );

  @override
  Future<List<ExcelArchive>> listValidatedArchives() => _remote.listValidatedArchives();

  @override
  Future<List<ExcelArchiveSheet>> getValidatedArchiveData(String id) => _remote.getValidatedArchiveData(id);

  @override
  Future<List<Lead>> getValidatedArchiveLeads(String id) => _remote.getValidatedArchiveLeads(id);

  @override
  Future<void> deleteValidatedArchive(String id) => _remote.deleteValidatedArchive(id);

  @override
  Future<Sale> createSale({
    required String businessName,
    String? reviewLink,
    String? salesmanId,
    String? salesmanName,
    double price = 0,
    double salesmanPrice = 0,
    SaleStatus status = SaleStatus.orderPlaced,
  }) =>
      _remote.createSale(
        businessName: businessName,
        reviewLink: reviewLink,
        salesmanId: salesmanId,
        salesmanName: salesmanName,
        price: price,
        salesmanPrice: salesmanPrice,
        status: status,
      );

  @override
  Future<List<Sale>> listSales({String? salesmanId}) => _remote.listSales(salesmanId: salesmanId);

  @override
  Future<Sale> updateSale(
    String id, {
    String? businessName,
    String? reviewLink,
    String? salesmanId,
    String? salesmanName,
    double? price,
    double? salesmanPrice,
    SaleStatus? status,
  }) =>
      _remote.updateSale(
        id,
        businessName: businessName,
        reviewLink: reviewLink,
        salesmanId: salesmanId,
        salesmanName: salesmanName,
        price: price,
        salesmanPrice: salesmanPrice,
        status: status,
      );

  @override
  Future<void> deleteSale(String id) => _remote.deleteSale(id);

  @override
  Future<SalesStats> getSalesStats({String? salesmanId}) => _remote.getSalesStats(salesmanId: salesmanId);
}
