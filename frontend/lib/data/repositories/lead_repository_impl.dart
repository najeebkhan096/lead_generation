import 'dart:typed_data';

import '../../domain/entities/lead.dart';
import '../../domain/entities/multi_search_snapshot.dart';
import '../../domain/entities/state_city_scan_snapshot.dart';
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
  Future<Uint8List> exportMultiExcel() => _remote.exportMultiExcel();

  @override
  Future<List<Lead>> getSavedBusinesses() => _remote.getSavedLeads();

  @override
  Future<List<Lead>> getWebsiteLeads() => _remote.getWebsiteLeads();

  @override
  Future<void> deleteWebsiteLead(String leadId) => _remote.deleteWebsiteLead(leadId);

  @override
  Future<int> deleteWebsiteLeadsByCategory(String category) =>
      _remote.deleteWebsiteLeadsByCategory(category);

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
  Future<void> startStateScan({
    required List<String> categories,
    int concurrency = 4,
    String dateRange = '30',
    int maxResultsPerCity = 160,
    bool analyze = false,
  }) =>
      _remote.startStateScan(
        categories: categories,
        concurrency: concurrency,
        dateRange: dateRange,
        maxResultsPerCity: maxResultsPerCity,
        analyze: analyze,
      );

  @override
  Future<StateCityScanSnapshot> getStateScanStatus() => _remote.getStateScanStatus();

  @override
  Future<void> cancelStateScan() => _remote.cancelStateScan();

  @override
  Future<void> pauseStateScan() => _remote.pauseStateScan();

  @override
  Future<void> resumeStateScan() => _remote.resumeStateScan();

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
  Future<String> resumeExcelArchive(String id) => _remote.resumeExcelArchive(id);

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
    LeadStatus leadStatus = LeadStatus.newLead,
    double priceChargedToClient = 0,
    ClientPaymentStatus clientPaymentStatus = ClientPaymentStatus.pending,
    String? clientPaymentMethod,
    double employeePaymentAmount = 0,
    EmployeePaymentStatus employeePaymentStatus = EmployeePaymentStatus.pending,
    double clientAmountReceived = 0,
    double removalCost = 0,
  }) =>
      _remote.createSale(
        businessName: businessName,
        reviewLink: reviewLink,
        salesmanId: salesmanId,
        salesmanName: salesmanName,
        leadStatus: leadStatus,
        priceChargedToClient: priceChargedToClient,
        clientPaymentStatus: clientPaymentStatus,
        clientPaymentMethod: clientPaymentMethod,
        employeePaymentAmount: employeePaymentAmount,
        employeePaymentStatus: employeePaymentStatus,
        clientAmountReceived: clientAmountReceived,
        removalCost: removalCost,
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
    LeadStatus? leadStatus,
    double? priceChargedToClient,
    ClientPaymentStatus? clientPaymentStatus,
    String? clientPaymentMethod,
    double? employeePaymentAmount,
    EmployeePaymentStatus? employeePaymentStatus,
    double? clientAmountReceived,
    double? removalCost,
  }) =>
      _remote.updateSale(
        id,
        businessName: businessName,
        reviewLink: reviewLink,
        salesmanId: salesmanId,
        salesmanName: salesmanName,
        leadStatus: leadStatus,
        priceChargedToClient: priceChargedToClient,
        clientPaymentStatus: clientPaymentStatus,
        clientPaymentMethod: clientPaymentMethod,
        employeePaymentAmount: employeePaymentAmount,
        employeePaymentStatus: employeePaymentStatus,
        clientAmountReceived: clientAmountReceived,
        removalCost: removalCost,
      );

  @override
  Future<void> deleteSale(String id) => _remote.deleteSale(id);

  @override
  Future<SalesStats> getSalesStats({String? salesmanId}) => _remote.getSalesStats(salesmanId: salesmanId);
}
