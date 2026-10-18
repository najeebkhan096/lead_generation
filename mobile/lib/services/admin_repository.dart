import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/client_record.dart';
import '../models/sale.dart';
import '../models/sales_user.dart';
import 'api_service.dart';

/// Admin reads and writes over the backend REST API.
///
/// Admins go through the backend (Admin SDK) rather than Firestore because
/// firestore.rules only let a signed-in account read its own `sales` and
/// `users` documents.
class AdminRepository {
  static const Duration _timeout = Duration(seconds: 8);

  String get _baseUrl => ApiService.baseUrl;

  Future<List<SalesUser>> listUsers() async {
    final data = await _send('GET', '/api/users', failure: 'Failed to load users');
    final list = data['users'] as List<dynamic>? ?? const [];
    return list.map((e) => SalesUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SalesUser> setUserApproved(String userId, {required bool approved}) async {
    final data = await _send('PATCH', '/api/users/$userId', body: {'approved': approved}, failure: 'Failed to update approval');
    return SalesUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// `null` puts the salesman back on the default limit.
  Future<SalesUser> setUserDailyLeadLimit(String userId, int? limit) async {
    final data = await _send('PATCH', '/api/users/$userId', body: {'dailyLeadLimit': limit}, failure: 'Failed to update the daily limit');
    return SalesUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<SalesUser> setUserRole(String userId, String role) async {
    final data = await _send('PATCH', '/api/users/$userId', body: {'role': role}, failure: 'Failed to update role');
    return SalesUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<List<Sale>> listSales() async {
    final data = await _send('GET', '/api/sales', failure: 'Failed to load sales');
    final list = data['sales'] as List<dynamic>? ?? const [];
    return list.map((e) => Sale.fromJsonMap(e as Map<String, dynamic>)).toList();
  }

  Future<Sale> createSale(Map<String, dynamic> body) async {
    final data = await _send('POST', '/api/sales', body: body, failure: 'Failed to create sale');
    return Sale.fromJsonMap(data['sale'] as Map<String, dynamic>);
  }

  Future<Sale> updateSale(String saleId, Map<String, dynamic> body) async {
    final data = await _send('PATCH', '/api/sales/$saleId', body: body, failure: 'Failed to update sale');
    return Sale.fromJsonMap(data['sale'] as Map<String, dynamic>);
  }

  Future<void> deleteSale(String saleId) async {
    await _send('DELETE', '/api/sales/$saleId', failure: 'Failed to delete sale');
  }

  Future<List<ClientRecord>> listClients() async {
    final data = await _send('GET', '/api/clients', failure: 'Failed to load clients');
    final list = data['clients'] as List<dynamic>? ?? const [];
    return list.map((e) => ClientRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ClientRecord> createClient({required String name, required String mapsUrl}) async {
    final data = await _send('POST', '/api/clients', body: {'businessName': name, 'mapsUrl': mapsUrl}, failure: 'Failed to add client');
    return ClientRecord.fromJson(data['client'] as Map<String, dynamic>);
  }

  Future<ClientRecord> updateClient(String id, {String? name, String? mapsUrl}) async {
    final body = <String, dynamic>{'businessName': ?name, 'mapsUrl': ?mapsUrl};
    final data = await _send('PATCH', '/api/clients/$id', body: body, failure: 'Failed to update client');
    return ClientRecord.fromJson(data['client'] as Map<String, dynamic>);
  }

  Future<void> deleteClient(String id) async {
    await _send('DELETE', '/api/clients/$id', failure: 'Failed to delete client');
  }

  /// Flags sales created before [before] so their payments stop counting
  /// (or undoes it with [restore]). Nothing is deleted. With [apply] false
  /// it only reports how many sales would be affected.
  Future<ArchiveResult> archivePayments({required DateTime before, bool restore = false, bool apply = false}) async {
    final data = await _send(
      'POST',
      '/api/sales/archive-payments',
      body: {'before': before.toUtc().toIso8601String(), 'restore': restore, 'apply': apply},
      failure: 'Failed to update payment records',
    );
    final r = data['result'] as Map<String, dynamic>? ?? const {};
    return ArchiveResult(
      matched: (r['matched'] as num?)?.toInt() ?? 0,
      updated: (r['updated'] as num?)?.toInt() ?? 0,
      alreadyArchived: (r['alreadyArchived'] as num?)?.toInt() ?? 0,
      totalSales: (r['totalSales'] as num?)?.toInt() ?? 0,
    );
  }

  /// One request; returns the decoded JSON object (empty for an empty body).
  /// Throws an [Exception] whose message is safe to show the admin.
  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required String failure,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await request.send().timeout(_timeout));
    } catch (_) {
      throw Exception('Could not reach the server. Check the connection and that the backend is running.');
    }
    final decoded = response.body.isEmpty ? null : _tryDecode(response.body);
    if (response.statusCode >= 400) {
      final detail = decoded is Map ? decoded['error'] : null;
      throw Exception(detail is String && detail.isNotEmpty ? detail : '$failure (${response.statusCode})');
    }
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}

/// Outcome of [AdminRepository.archivePayments].
class ArchiveResult {
  const ArchiveResult({required this.matched, required this.updated, required this.alreadyArchived, required this.totalSales});

  /// Sales the operation applies to.
  final int matched;

  /// Sales actually written (0 for a dry run).
  final int updated;
  final int alreadyArchived;
  final int totalSales;
}
