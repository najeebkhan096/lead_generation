import 'package:flutter/widgets.dart';

import '../models/client_record.dart';
import '../models/sale.dart';
import '../models/sales_user.dart';
import '../utils/admin_analytics.dart';
import 'admin_repository.dart';

/// The admin app's single source of truth: one load of users + sales,
/// shared by every tab and detail page through [AdminScope]. Writes go to
/// the backend and then update the in-memory lists, so every screen
/// (counts, ongoing/completed splits, payouts) stays consistent without a
/// refetch per screen.
class AdminData extends ChangeNotifier {
  AdminData({AdminRepository? repository}) : _repo = repository ?? AdminRepository();

  final AdminRepository _repo;

  AdminSnapshot _snapshot = AdminSnapshot.empty;
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  String? _warning;

  AdminSnapshot get snapshot => _snapshot;

  /// True during the first load or a manual refresh.
  bool get loading => _loading;

  /// True once a load has finished (successfully or not) — lets screens
  /// tell "still loading for the first time" from "loaded, nothing there".
  bool get loadedOnce => _loadedOnce;

  /// Last load failure, shown only when there is nothing to show instead.
  String? get error => _error;

  /// A non-fatal problem: something optional failed to load (the client
  /// list) while sales and users did. The screens still work.
  String? get warning => _warning;

  bool get hasData => _snapshot.sales.isNotEmpty || _snapshot.users.isNotEmpty || _snapshot.clientRecords.isNotEmpty;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _warning = null;
    notifyListeners();
    try {
      // Sales and users are essential. The client list is not: if it fails
      // (e.g. an older backend without /api/clients) the app still shows
      // everything, with clients derived from the sales.
      final clients = _repo.listClients().then<List<ClientRecord>?>((c) => c).catchError((Object e) {
        _warning = 'Couldn\'t load the client list: ${e.toString().replaceFirst('Exception: ', '')}';
        return null;
      });
      final results = await Future.wait([_repo.listSales(), _repo.listUsers(), clients]);
      _snapshot = AdminSnapshot(
        sales: results[0] as List<Sale>,
        users: results[1] as List<SalesUser>,
        clientRecords: (results[2] as List<ClientRecord>?) ?? _snapshot.clientRecords,
      );
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      _loadedOnce = true;
      notifyListeners();
    }
  }

  // ── Sales ────────────────────────────────────────────────────

  Future<Sale> createSale(Map<String, dynamic> body) async {
    final created = await _repo.createSale(body);
    _replaceSales([created, ..._snapshot.sales]);
    return created;
  }

  Future<Sale> updateSale(String id, Map<String, dynamic> body) async {
    final updated = await _repo.updateSale(id, body);
    _replaceSales([for (final s in _snapshot.sales) s.id == id ? updated : s]);
    return updated;
  }

  Future<void> deleteSale(String id) async {
    await _repo.deleteSale(id);
    _replaceSales([for (final s in _snapshot.sales) if (s.id != id) s]);
  }

  /// Marks every given sale's salesman payout as paid. Stops at the first
  /// failure; sales already updated stay updated and are reflected on screen.
  Future<int> markPayoutsPaid(Iterable<Sale> sales) async {
    var done = 0;
    for (final s in sales) {
      await updateSale(s.id, {'employeePaymentStatus': EmployeePaymentStatus.paid.name});
      done++;
    }
    return done;
  }

  /// Previews or applies the fresh start; reloads after a write.
  Future<ArchiveResult> archivePayments({required DateTime before, bool restore = false, bool apply = false}) async {
    final result = await _repo.archivePayments(before: before, restore: restore, apply: apply);
    if (apply) await load();
    return result;
  }

  // ── Clients ──────────────────────────────────────────────────

  Future<ClientRecord> addClient({required String name, required String mapsUrl}) async {
    final created = await _repo.createClient(name: name, mapsUrl: mapsUrl);
    _replaceClients([..._snapshot.clientRecords, created]);
    return created;
  }

  Future<ClientRecord> editClient(String id, {String? name, String? mapsUrl}) async {
    final updated = await _repo.updateClient(id, name: name, mapsUrl: mapsUrl);
    _replaceClients([for (final c in _snapshot.clientRecords) c.id == id ? updated : c]);
    return updated;
  }

  Future<void> removeClient(String id) async {
    await _repo.deleteClient(id);
    _replaceClients([for (final c in _snapshot.clientRecords) if (c.id != id) c]);
  }

  // ── Users ────────────────────────────────────────────────────

  Future<void> setApproved(SalesUser user, bool approved) async {
    final updated = await _repo.setUserApproved(user.id, approved: approved);
    _replaceUser(updated);
  }

  /// `null` puts the salesman back on the default limit.
  Future<void> setDailyLeadLimit(SalesUser user, int? limit) async {
    final updated = await _repo.setUserDailyLeadLimit(user.id, limit);
    _replaceUser(updated);
  }

  Future<void> setRole(SalesUser user, String role) async {
    final updated = await _repo.setUserRole(user.id, role);
    _replaceUser(updated);
  }

  void _replaceSales(List<Sale> sales) {
    _snapshot = AdminSnapshot(sales: sales, users: _snapshot.users, clientRecords: _snapshot.clientRecords);
    notifyListeners();
  }

  void _replaceClients(List<ClientRecord> clients) {
    _snapshot = AdminSnapshot(sales: _snapshot.sales, users: _snapshot.users, clientRecords: clients);
    notifyListeners();
  }

  void _replaceUser(SalesUser updated) {
    _snapshot = AdminSnapshot(
      sales: _snapshot.sales,
      users: [for (final u in _snapshot.users) u.id == updated.id ? updated : u],
      clientRecords: _snapshot.clientRecords,
    );
    notifyListeners();
  }
}

/// Exposes the [AdminData] to the admin subtree and rebuilds dependents
/// when it changes.
class AdminScope extends InheritedNotifier<AdminData> {
  const AdminScope({super.key, required AdminData data, required super.child}) : super(notifier: data);

  /// Watches: the calling widget rebuilds when the data changes.
  static AdminData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AdminScope>();
    assert(scope != null, 'AdminScope missing above ${context.widget.runtimeType}');
    return scope!.notifier!;
  }

  /// Reads without subscribing — for event handlers.
  static AdminData read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AdminScope>();
    assert(scope != null, 'AdminScope missing above ${context.widget.runtimeType}');
    return scope!.notifier!;
  }
}
