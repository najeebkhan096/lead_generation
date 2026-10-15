import '../models/client_record.dart';
import '../models/sale.dart';
import 'maps_url.dart';
import '../models/sales_user.dart';

/// Figures for a set of sales, shared by every admin screen so "ongoing",
/// "completed" and "payable" mean the same thing everywhere.
///
/// The process: deal **locked** → **removal** → **payment** → completed.
///
/// * **Ongoing**   — locked + removal + awaiting payment.
/// * **Completed** — the client has paid.
/// * **Payable**   — completed orders whose salesman payout is still pending
///   (what the business owes right now).
/// * **Expected**  — payouts attached to ongoing orders (still in the
///   pipeline, not yet owed).
///
/// Orders flagged [Sale.paymentsArchived] (from before the fresh start) are
/// counted as orders — they keep their client and stage — but contribute no
/// money to any figure below.
///
/// Two currencies are never mixed: the price billed to clients is USD,
/// everything else is PKR.
class SalesRollup {
  SalesRollup(this.sales)
      : ongoing = sales.where((s) => s.status.isOngoing).length,
        locked = sales.where((s) => s.status == SaleStatus.newSale).length,
        removal = sales.where((s) => s.status == SaleStatus.inProgress).length,
        awaitingPayment = sales.where((s) => s.status == SaleStatus.payment).length,
        completed = sales.where((s) => s.status == SaleStatus.completed).length,
        cancelled = sales.where((s) => s.status == SaleStatus.cancelled).length,
        paidPkr = _sum(sales, (s) => _counts(s) && s.status != SaleStatus.cancelled && s.employeePaymentStatus == EmployeePaymentStatus.paid, (s) => s.employeePaymentAmount),
        payablePkr = _sum(sales, (s) => _counts(s) && s.status == SaleStatus.completed && s.employeePaymentStatus == EmployeePaymentStatus.pending, (s) => s.employeePaymentAmount),
        expectedPkr = _sum(sales, (s) => _counts(s) && s.status.isOngoing && s.employeePaymentStatus == EmployeePaymentStatus.pending, (s) => s.employeePaymentAmount),
        billedUsd = _sum(sales, (s) => _counts(s) && s.status != SaleStatus.cancelled, (s) => s.priceChargedToClient),
        receivedPkr = _sum(sales, (s) => _counts(s) && s.status != SaleStatus.cancelled, (s) => s.clientAmountReceived),
        profitPkr = _sum(sales, (s) => _counts(s) && s.status != SaleStatus.cancelled, (s) => s.profit);

  final List<Sale> sales;
  final int ongoing;
  final int locked;
  final int removal;
  final int awaitingPayment;
  final int completed;
  final int cancelled;
  final double paidPkr;
  final double payablePkr;
  final double expectedPkr;
  final double billedUsd;
  final double receivedPkr;
  final double profitPkr;

  int get total => sales.length;

  /// Orders whose payments no longer count (before the fresh start).
  int get archived => sales.where((s) => s.paymentsArchived).length;

  /// Completed orders with a payout still owed — what "Mark as paid" settles.
  List<Sale> get dueSales => sales
      .where((s) => _counts(s) && s.status == SaleStatus.completed && s.employeePaymentStatus == EmployeePaymentStatus.pending && s.employeePaymentAmount > 0)
      .toList();

  /// Share of concluded orders that were delivered. A cancelled order is a
  /// lost one, so it counts against the rate; ongoing orders are ignored.
  double get completionRate {
    final closed = completed + cancelled;
    return closed == 0 ? 0 : completed / closed;
  }

  List<Sale> byStatus(Iterable<SaleStatus> statuses) =>
      sales.where((s) => statuses.contains(s.status)).toList();

  static bool _counts(Sale s) => !s.paymentsArchived;

  static double _sum(List<Sale> sales, bool Function(Sale) test, double Function(Sale) value) {
    var total = 0.0;
    for (final s in sales) {
      if (test(s)) total += value(s);
    }
    return total;
  }
}

/// One salesman and everything they sold.
class SalesmanSummary {
  SalesmanSummary({required this.user, required List<Sale> sales}) : rollup = SalesRollup(sales);

  final SalesUser user;
  final SalesRollup rollup;

  List<Sale> get sales => rollup.sales;
}

/// One client business and every order placed for it.
class ClientSummary {
  ClientSummary({required this.name, required List<Sale> sales, this.record})
      : rollup = SalesRollup(sales),
        salesmen = {
          for (final s in sales)
            if ((s.salesmanName ?? '').trim().isNotEmpty) s.salesmanName!.trim(),
        }.toList()
          ..sort();

  final String name;
  final SalesRollup rollup;

  /// The stored client (name + Google Maps link); null for a business that
  /// only exists on older sales.
  final ClientRecord? record;

  String? get mapsUrl => record?.hasMapsUrl == true ? record!.mapsUrl : null;

  /// Names of the salesmen who handled this client's orders.
  final List<String> salesmen;

  List<Sale> get sales => rollup.sales;

  /// A client is "active" while at least one order is still ongoing.
  bool get isActive => rollup.ongoing > 0;

  DateTime? get lastActivity {
    DateTime? latest;
    for (final s in sales) {
      final d = s.updatedAt ?? s.createdAt;
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    return latest;
  }
}

/// Everything the admin screens show, computed once per data load.
class AdminSnapshot {
  AdminSnapshot({required this.sales, required this.users, this.clientRecords = const []})
      : overall = SalesRollup(sales),
        salesmen = _salesmen(sales, users),
        clients = _clients(sales, clientRecords);

  static final empty = AdminSnapshot(sales: const [], users: const []);

  final List<Sale> sales;
  final List<SalesUser> users;

  /// The stored client list (name + Google Maps link).
  final List<ClientRecord> clientRecords;
  final SalesRollup overall;

  /// Approved salesman accounts (admins and unapproved users are not
  /// assignable), busiest first.
  final List<SalesmanSummary> salesmen;

  /// Client businesses, most recently active first.
  final List<ClientSummary> clients;

  int get pendingApprovals => users.where((u) => !u.approved).length;

  /// Sales not assigned to any account.
  List<Sale> get unassigned => sales.where((s) => s.salesmanId == null && (s.salesmanName ?? '').trim().isEmpty).toList();

  SalesmanSummary? salesmanFor(String? id) {
    if (id == null) return null;
    for (final s in salesmen) {
      if (s.user.id == id) return s;
    }
    return null;
  }

  /// Every sale a given user owns — by account id, falling back to the
  /// stored name for orders recorded before ids were captured.
  static List<Sale> salesOf(SalesUser user, List<Sale> sales) {
    final name = user.name.trim().toLowerCase();
    return sales.where((s) {
      if (s.salesmanId != null) return s.salesmanId == user.id;
      final n = s.salesmanName?.trim().toLowerCase();
      return n != null && n.isNotEmpty && n == name;
    }).toList();
  }

  static List<SalesmanSummary> _salesmen(List<Sale> sales, List<SalesUser> users) {
    final list = [
      for (final u in users)
        if (u.role != 'admin') SalesmanSummary(user: u, sales: salesOf(u, sales)),
    ];
    list.sort((a, b) {
      final byTotal = b.rollup.total.compareTo(a.rollup.total);
      return byTotal != 0 ? byTotal : a.user.name.toLowerCase().compareTo(b.user.name.toLowerCase());
    });
    return list;
  }

  /// Every stored client plus any business that only appears on a sale, so
  /// nothing recorded earlier drops out of the list.
  static List<ClientSummary> _clients(List<Sale> sales, List<ClientRecord> records) {
    final byKey = <String, ClientRecord>{
      for (final r in records)
        if (clientNameKey(r.name).isNotEmpty) clientNameKey(r.name): r,
    };
    final byId = {for (final r in records) r.id: r};

    final groups = <String, List<Sale>>{};
    final names = <String, String>{};
    for (final s in sales) {
      final record = s.clientId != null ? byId[s.clientId] : null;
      final key = record != null ? clientNameKey(record.name) : clientNameKey(s.businessName);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(s);
      names.putIfAbsent(key, () => (record?.name ?? s.businessName).trim());
    }
    for (final e in byKey.entries) {
      groups.putIfAbsent(e.key, () => []);
      names[e.key] = e.value.name.trim();
    }

    final list = [
      for (final e in groups.entries) ClientSummary(name: names[e.key]!, sales: e.value, record: byKey[e.key]),
    ];
    list.sort((a, b) {
      final ad = a.lastActivity;
      final bd = b.lastActivity;
      if (ad == null && bd == null) return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return list;
  }
}

/// "PKR 12,500" — whole rupees with thousands separators.
String formatPkr(num amount) => 'PKR ${_grouped(amount.round())}';

/// "$1,250" — whole dollars with thousands separators.
String formatUsd(num amount) => '\$${_grouped(amount.round())}';

String _grouped(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}$buffer';
}
