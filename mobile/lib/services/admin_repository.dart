import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/client_record.dart';
import '../models/sale.dart';
import '../models/sales_user.dart';
import 'admin_records.dart';

/// Admin reads and writes, straight from Firestore — no backend server.
///
/// firestore.rules let an admin (role 'admin', approved) read every user, sale
/// and client and write sales, clients and the account fields an admin sets
/// (approval, daily limit, role). The record shapes and checks are in
/// admin_records.dart, mirroring the backend stores so the web console and the
/// phone write the same documents.
class AdminRepository {
  AdminRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  // Read lazily so building the repository does not touch Firebase (tests build one without it).
  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  // ── Users ───────────────────────────────────────────────────────────

  Future<List<SalesUser>> listUsers() => _run(() async {
        final snap = await _db.collection('users').get();
        final users = [for (final d in snap.docs) SalesUser.fromJson(userJson(d.id, d.data()))];
        // Waiting for approval first, then by name — as the backend lists them.
        users.sort((a, b) {
          if (a.approved != b.approved) return a.approved ? 1 : -1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return users;
      }, 'Failed to load users');

  Future<SalesUser> setUserApproved(String userId, {required bool approved}) =>
      _updateUser(userId, {'approved': approved});

  /// `null` puts the salesman back on the default limit.
  Future<SalesUser> setUserDailyLeadLimit(String userId, int? limit) {
    checkDailyLeadLimit(limit);
    return _updateUser(userId, {'dailyLeadLimit': limit ?? FieldValue.delete()});
  }

  Future<SalesUser> setUserRole(String userId, String role) {
    checkRole(role);
    return _updateUser(userId, {'role': role});
  }

  Future<SalesUser> _updateUser(String userId, Map<String, dynamic> patch) => _run(() async {
        final ref = _db.collection('users').doc(userId);
        try {
          await ref.update({...patch, 'updatedAt': FieldValue.serverTimestamp()});
        } on FirebaseException catch (e) {
          if (e.code == 'not-found') throw const AdminInputException('User not found');
          rethrow;
        }
        final saved = await ref.get();
        return SalesUser.fromJson(userJson(saved.id, saved.data() ?? const {}));
      }, 'Failed to update the user');

  // ── Sales ───────────────────────────────────────────────────────────

  Future<List<Sale>> listSales() => _run(
        () async => [for (final s in await _salesJson()) Sale.fromJsonMap(s)],
        'Failed to load sales',
      );

  Future<Sale> createSale(Map<String, dynamic> body) => _run(() async {
        final ref = _db.collection('sales').doc();
        await ref.set(newSaleDocument(body));
        return _readSale(ref.id);
      }, 'Failed to create sale');

  Future<Sale> updateSale(String saleId, Map<String, dynamic> body) => _run(() async {
        final ref = _db.collection('sales').doc(saleId);
        await ref.update({...saleFields(body), 'updatedAt': FieldValue.serverTimestamp()});
        return _readSale(saleId);
      }, 'Failed to update sale');

  Future<void> deleteSale(String saleId) => _run(
        () => _db.collection('sales').doc(saleId).delete(),
        'Failed to delete sale',
      );

  Future<Sale> _readSale(String id) async {
    final snap = await _db.collection('sales').doc(id).get();
    return Sale.fromJsonMap(saleJson(snap.id, snap.data() ?? const {}));
  }

  /// Every sale as the admin feed shows it, newest first.
  Future<List<Map<String, dynamic>>> _salesJson() async {
    final snap = await _db.collection('sales').get();
    final rows = [for (final d in snap.docs) saleJson(d.id, d.data())];
    rows.sort((a, b) => ((b['createdAt'] as String?) ?? '').compareTo((a['createdAt'] as String?) ?? ''));
    return rows;
  }

  // ── Clients ─────────────────────────────────────────────────────────

  Future<List<ClientRecord>> listClients() => _run(() async {
        final snap = await _db.collection('clients').get();
        final clients = [for (final d in snap.docs) ClientRecord.fromJson(clientJson(d.id, d.data()))];
        clients.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return clients;
      }, 'Failed to load clients');

  Future<ClientRecord> createClient({required String name, required String mapsUrl}) => _run(() async {
        final clean = cleanClientName(name);
        final url = requireMapsUrl(mapsUrl);
        final ref = _db.collection('clients').doc(clientDocId(clean));
        final existing = await ref.get();
        if (existing.exists) {
          throw AdminInputException('"${existing.data()?['businessName']}" is already a client');
        }
        await ref.set({
          'businessName': clean,
          'nameKey': clientNameKey(clean),
          'mapsUrl': url,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return _readClient(ref.id);
      }, 'Failed to add client');

  Future<ClientRecord> updateClient(String id, {String? name, String? mapsUrl}) => _run(() async {
        final ref = _db.collection('clients').doc(id);
        final existing = await ref.get();
        if (!existing.exists) throw const AdminInputException('Client not found');
        final patch = <String, dynamic>{};
        if (name != null) {
          final clean = cleanClientName(name);
          final key = clientNameKey(clean);
          if (key != existing.data()?['nameKey']) {
            final clash = await _db.collection('clients').where('nameKey', isEqualTo: key).limit(1).get();
            if (clash.docs.isNotEmpty && clash.docs.first.id != id) {
              throw AdminInputException('"${clash.docs.first.data()['businessName']}" is already a client');
            }
          }
          patch['businessName'] = clean;
          patch['nameKey'] = key;
        }
        if (mapsUrl != null) patch['mapsUrl'] = requireMapsUrl(mapsUrl);
        await ref.update({...patch, 'updatedAt': FieldValue.serverTimestamp()});
        return _readClient(id);
      }, 'Failed to update client');

  Future<void> deleteClient(String id) => _run(
        () => _db.collection('clients').doc(id).delete(),
        'Failed to delete client',
      );

  Future<ClientRecord> _readClient(String id) async {
    final snap = await _db.collection('clients').doc(id).get();
    return ClientRecord.fromJson(clientJson(snap.id, snap.data() ?? const {}));
  }

  // ── Fresh start ─────────────────────────────────────────────────────

  /// Flags sales created before [before] so their payments stop counting
  /// (or undoes it with [restore]). Nothing is deleted. With [apply] false
  /// it only reports how many sales would be affected.
  Future<ArchiveResult> archivePayments({required DateTime before, bool restore = false, bool apply = false}) => _run(() async {
        final sales = await _salesJson();
        final targets = selectForArchive(sales, before: before, restore: restore);
        var updated = 0;
        if (apply) {
          const batchSize = 400;
          for (var i = 0; i < targets.length; i += batchSize) {
            final chunk = targets.skip(i).take(batchSize).toList();
            final batch = _db.batch();
            for (final s in chunk) {
              // updatedAt is left alone so lists ordered by it do not reshuffle.
              batch.update(_db.collection('sales').doc(s['id'] as String), {
                'paymentsArchived': !restore,
                'paymentsArchivedAt': restore ? null : FieldValue.serverTimestamp(),
              });
            }
            await batch.commit();
            updated += chunk.length;
          }
        }
        return ArchiveResult(
          matched: targets.length,
          updated: updated,
          alreadyArchived: sales.where((s) => s['paymentsArchived'] == true).length,
          totalSales: sales.length,
        );
      }, 'Failed to update payment records');

  /// Runs one Firestore operation. Input errors pass through as they are; a
  /// refused or failed read or write becomes a message the admin can act on.
  Future<T> _run<T>(Future<T> Function() operation, String failure) async {
    try {
      return await operation();
    } on AdminInputException {
      rethrow;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw Exception('Only an admin can make this change.');
      if (e.code == 'not-found') throw Exception('Not found. It may have been deleted.');
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        throw Exception('Could not reach Firebase. Check the connection.');
      }
      throw Exception('$failure (${e.code})');
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
