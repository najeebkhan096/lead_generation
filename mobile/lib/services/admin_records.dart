import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// The admin console's records, straight from Firestore: how documents become
/// the JSON-shaped maps the admin models read, and how admin input becomes a
/// document. Mirrors the backend stores (backend/src/modules/sales/saleStore.js,
/// users/userStore.js, clients/clientStore.js, lib/mapsUrl.js), so the phone and
/// the web console read and write the same documents the same way.
///
/// Pure functions, no I/O: the Firestore calls are in admin_repository.dart.

/// Deal stages a sale can be in (`leadStatus`).
const saleLeadStatuses = ['new', 'in_progress', 'payment', 'completed', 'cancelled'];

/// Whether the client has paid what they were charged (USD).
const clientPaymentStatuses = ['pending', 'paid', 'stuck', 'received', 'in_process'];

/// Whether the salesman has been paid their cut (PKR).
const employeePaymentStatuses = ['pending', 'paid'];

/// The most new leads a salesman may be allowed per day.
const maxDailyLeadLimit = 1000;

/// The limit a salesman has when no admin set one. Matches DEFAULT_DAILY_LEAD_LIMIT.
const defaultDailyLeadLimit = 10;

final _googleHost = RegExp(r'(^|\.)google\.[a-z.]{2,}$', caseSensitive: false);
const _googleShortHosts = {'goo.gl', 'maps.app.goo.gl', 'g.page', 'g.co', 'share.google'};

// ── Documents → records ───────────────────────────────────────────────────

String? _iso(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
  return null;
}

String? _nonEmpty(Object? value) {
  final s = value is String ? value.trim() : '';
  return s.isEmpty ? null : s;
}

double _number(Object? value) => value is num ? value.toDouble() : 0;

/// A sale as the admin feed shows it (the shape [Sale.fromJsonMap] reads).
Map<String, dynamic> saleJson(String id, Map<String, dynamic> d) => {
      'id': id,
      'businessName': _nonEmpty(d['businessName']) ?? '',
      'clientId': d['clientId'],
      'reviewLink': d['reviewLink'],
      'salesmanId': d['salesmanId'],
      'salesmanName': d['salesmanName'],
      'leadStatus': saleLeadStatuses.contains(d['leadStatus']) ? d['leadStatus'] : 'new',
      'priceChargedToClient': _number(d['priceChargedToClient']),
      'clientPaymentStatus': clientPaymentStatuses.contains(d['clientPaymentStatus']) ? d['clientPaymentStatus'] : 'pending',
      'clientPaymentMethod': d['clientPaymentMethod'],
      'employeePaymentAmount': _number(d['employeePaymentAmount']),
      'employeePaymentStatus': employeePaymentStatuses.contains(d['employeePaymentStatus']) ? d['employeePaymentStatus'] : 'pending',
      'clientAmountReceived': _number(d['clientAmountReceived']),
      'removalCost': _number(d['removalCost']),
      'paymentsArchived': d['paymentsArchived'] == true,
      'createdAt': _iso(d['createdAt']),
      'updatedAt': _iso(d['updatedAt']),
    };

/// A salesman account as the admin console shows it (the shape [SalesUser.fromJson] reads).
Map<String, dynamic> userJson(String id, Map<String, dynamic> d) => {
      'id': id,
      'name': _nonEmpty(d['name']) ?? _nonEmpty(d['email']) ?? 'Unnamed',
      'email': _nonEmpty(d['email']),
      'photoURL': _nonEmpty(d['photoURL']),
      'role': d['role'] is String ? d['role'] : 'salesman',
      'approved': d['approved'] == true,
      'dailyLeadLimit': d['dailyLeadLimit'] is int ? d['dailyLeadLimit'] : defaultDailyLeadLimit,
      'createdAt': _iso(d['createdAt']),
      'lastLoginAt': _iso(d['lastLoginAt']),
    };

/// A client as the admin console shows it (the shape [ClientRecord.fromJson] reads).
Map<String, dynamic> clientJson(String id, Map<String, dynamic> d) => {
      'id': id,
      'businessName': _nonEmpty(d['businessName']) ?? '',
      'mapsUrl': _nonEmpty(d['mapsUrl']),
      'createdAt': _iso(d['createdAt']),
      'updatedAt': _iso(d['updatedAt']),
    };

// ── Input → documents ─────────────────────────────────────────────────────

/// Thrown for input an admin got wrong; the message is shown as it is.
class AdminInputException implements Exception {
  const AdminInputException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// `Number(x) || 0` in the backend: a number, or 0 for anything that is not one.
double _money(Object? value) {
  final n = value is num ? value.toDouble() : double.tryParse('$value');
  return (n == null || n.isNaN) ? 0 : n;
}

String? _trimmedOrNull(Object? value) {
  final s = value == null ? '' : '$value'.trim();
  return s.isEmpty ? null : s;
}

T _oneOf<T>(Object? value, List<T> allowed, String field) {
  if (!allowed.contains(value)) {
    throw AdminInputException('$field must be one of: ${allowed.join(', ')}');
  }
  return value as T;
}

/// The sale fields an admin set in [input], checked the way the backend checks
/// them. Only the keys present in [input] are returned.
Map<String, dynamic> saleFields(Map<String, dynamic> input) {
  final out = <String, dynamic>{};
  if (input.containsKey('businessName')) out['businessName'] = '${input['businessName'] ?? ''}'.trim();
  if (input.containsKey('clientId')) out['clientId'] = _trimmedOrNull(input['clientId']);
  if (input.containsKey('reviewLink')) out['reviewLink'] = _trimmedOrNull(input['reviewLink']);
  if (input.containsKey('salesmanId')) out['salesmanId'] = _trimmedOrNull(input['salesmanId']);
  if (input.containsKey('salesmanName')) out['salesmanName'] = _trimmedOrNull(input['salesmanName']);
  if (input.containsKey('leadStatus')) {
    out['leadStatus'] = _oneOf(input['leadStatus'], saleLeadStatuses, 'leadStatus');
  }
  if (input.containsKey('priceChargedToClient')) out['priceChargedToClient'] = _money(input['priceChargedToClient']);
  if (input.containsKey('clientPaymentStatus')) {
    out['clientPaymentStatus'] = _oneOf(input['clientPaymentStatus'], clientPaymentStatuses, 'clientPaymentStatus');
  }
  if (input.containsKey('clientPaymentMethod')) out['clientPaymentMethod'] = _trimmedOrNull(input['clientPaymentMethod']);
  if (input.containsKey('employeePaymentAmount')) out['employeePaymentAmount'] = _money(input['employeePaymentAmount']);
  if (input.containsKey('employeePaymentStatus')) {
    out['employeePaymentStatus'] = _oneOf(input['employeePaymentStatus'], employeePaymentStatuses, 'employeePaymentStatus');
  }
  if (input.containsKey('clientAmountReceived')) out['clientAmountReceived'] = _money(input['clientAmountReceived']);
  if (input.containsKey('removalCost')) out['removalCost'] = _money(input['removalCost']);
  if (input.containsKey('paymentsArchived')) {
    final archived = input['paymentsArchived'] == true;
    out['paymentsArchived'] = archived;
    out['paymentsArchivedAt'] = archived ? FieldValue.serverTimestamp() : null;
  }
  return out;
}

/// The document a new sale is written as: every field, with the backend's defaults.
Map<String, dynamic> newSaleDocument(Map<String, dynamic> input) {
  final name = '${input['businessName'] ?? ''}'.trim();
  if (name.isEmpty) throw const AdminInputException('businessName is required');
  final fields = saleFields(input)..remove('paymentsArchived')..remove('paymentsArchivedAt');
  return {
    'businessName': name,
    'clientId': null,
    'reviewLink': null,
    'salesmanId': null,
    'salesmanName': null,
    'leadStatus': 'new',
    'priceChargedToClient': 0.0,
    'clientPaymentStatus': 'pending',
    'clientPaymentMethod': null,
    'employeePaymentAmount': 0.0,
    'employeePaymentStatus': 'pending',
    'clientAmountReceived': 0.0,
    'removalCost': 0.0,
    ...fields,
    'paymentsArchived': false,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// A daily limit: a whole number from 0 to [maxDailyLeadLimit], or null for the default.
void checkDailyLeadLimit(int? limit) {
  if (limit == null) return;
  if (limit < 0 || limit > maxDailyLeadLimit) {
    throw AdminInputException('dailyLeadLimit must be a whole number from 0 to $maxDailyLeadLimit, or null for the default');
  }
}

/// A role an account can have.
void checkRole(String role) {
  if (role != 'admin' && role != 'salesman') {
    throw const AdminInputException('role must be admin or salesman');
  }
}

// ── Clients ───────────────────────────────────────────────────────────────

/// The name as stored: single spaces, trimmed. Empty names are refused.
String cleanClientName(Object? value) {
  final name = '${value ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty) throw const AdminInputException('Business name is required');
  return name;
}

/// Lowercased, whitespace-collapsed name used to spot the same business.
/// (The backend also applies Unicode NFKC here; that matters only for
/// unusual characters, which is why it is noted rather than copied.)
String clientNameKey(String name) => name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Deterministic document id for a client name, so the same business always
/// lands on one document (clientDocId in clientStore.js).
String clientDocId(String name) {
  final digest = sha1.convert(utf8.encode(clientNameKey(name))).toString();
  return digest.substring(0, 20);
}

/// A Google Maps listing link, cleaned up, or null when [raw] is not one.
/// Adds a missing https:// and never rewrites the path or query.
/// Port of normalizeMapsUrl in backend/src/lib/mapsUrl.js.
String? normalizeMapsUrl(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim();
  if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;
  final withScheme = RegExp(r'^https?://', caseSensitive: false).hasMatch(text) ? text : 'https://$text';
  final Uri url;
  try {
    url = Uri.parse(withScheme);
  } catch (_) {
    return null;
  }
  if (url.scheme != 'https' && url.scheme != 'http') return null;
  final host = url.host.toLowerCase();
  if (!host.contains('.')) return null;
  if (!(_googleHost.hasMatch(host) || _googleShortHosts.contains(host))) return null;
  // "https://google.com" alone is a website, not a listing.
  if ((url.path.isEmpty || url.path == '/') && !url.hasQuery && !url.hasFragment) return null;
  return url.replace(scheme: 'https').toString();
}

/// A Maps link, required for a client; refused with the backend's message.
String requireMapsUrl(Object? raw) {
  final url = normalizeMapsUrl(raw);
  if (url == null) throw const AdminInputException('Enter a valid Google Maps link for the business');
  return url;
}

// ── Archive ───────────────────────────────────────────────────────────────

/// Which sales a fresh-start archive (or its undo) touches, as selectForArchive
/// in saleStore.js. A sale with no createdAt predates timestamps and counts as old.
List<Map<String, dynamic>> selectForArchive(
  List<Map<String, dynamic>> sales, {
  DateTime? before,
  bool restore = false,
}) {
  bool isOld(Map<String, dynamic> s) {
    if (before == null) return true;
    final created = s['createdAt'] as String?;
    if (created == null) return true;
    return DateTime.parse(created).isBefore(before);
  }

  return [
    for (final s in sales)
      if (restore ? s['paymentsArchived'] == true && isOld(s) : s['paymentsArchived'] != true && isOld(s)) s,
  ];
}
