import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/models/sale.dart';
import 'package:lead_mobile/models/sales_user.dart';
import 'package:lead_mobile/utils/admin_analytics.dart';

Sale sale(
  String id,
  String business, {
  SaleStatus status = SaleStatus.newSale,
  String? salesmanId,
  String? salesmanName,
  double payout = 0,
  EmployeePaymentStatus payoutStatus = EmployeePaymentStatus.pending,
  double price = 0,
  double received = 0,
  double removal = 0,
  DateTime? createdAt,
  bool archived = false,
}) =>
    Sale(
      id: id,
      businessName: business,
      status: status,
      salesmanId: salesmanId,
      salesmanName: salesmanName,
      employeePaymentAmount: payout,
      employeePaymentStatus: payoutStatus,
      priceChargedToClient: price,
      clientAmountReceived: received,
      removalCost: removal,
      createdAt: createdAt,
      paymentsArchived: archived,
    );

const ali = SalesUser(id: 'u1', name: 'Ali Khan', approved: true);
const sara = SalesUser(id: 'u2', name: 'Sara', approved: true);
const boss = SalesUser(id: 'a1', name: 'Boss', role: 'admin', approved: true);
const newbie = SalesUser(id: 'u3', name: 'Newbie');

void main() {
  group('SaleStatus', () {
    test('json matches the backend values', () {
      expect(SaleStatus.newSale.json, 'new');
      expect(SaleStatus.inProgress.json, 'in_progress');
      for (final s in SaleStatus.values) {
        expect(SaleStatus.fromJson(s.json), s);
      }
    });

    test('the process runs locked → removal → payment → completed', () {
      expect(SaleStatus.newSale.next, SaleStatus.inProgress);
      expect(SaleStatus.inProgress.next, SaleStatus.payment);
      expect(SaleStatus.payment.next, SaleStatus.completed);
      expect(SaleStatus.completed.next, isNull);
      expect(SaleStatus.cancelled.next, isNull);
      expect(SaleStatus.payment.json, 'payment');
      expect(SaleStatus.fromJson('payment'), SaleStatus.payment);
    });

    test('ongoing is locked, removal and payment', () {
      expect(SaleStatus.newSale.isOngoing, isTrue);
      expect(SaleStatus.inProgress.isOngoing, isTrue);
      expect(SaleStatus.payment.isOngoing, isTrue);
      expect(SaleStatus.completed.isOngoing, isFalse);
      expect(SaleStatus.cancelled.isOngoing, isFalse);
    });
  });

  group('SalesRollup', () {
    final rollup = SalesRollup([
      sale('1', 'A', status: SaleStatus.newSale, payout: 100),
      sale('2', 'A', status: SaleStatus.inProgress, payout: 200),
      sale('6', 'D', status: SaleStatus.payment, payout: 50),
      sale('3', 'B', status: SaleStatus.completed, payout: 500, price: 50, received: 14000, removal: 1000),
      sale('4', 'B', status: SaleStatus.completed, payout: 300, payoutStatus: EmployeePaymentStatus.paid, price: 30),
      sale('5', 'C', status: SaleStatus.cancelled, payout: 999, payoutStatus: EmployeePaymentStatus.paid, price: 70),
    ]);

    test('counts by stage', () {
      expect(rollup.total, 6);
      expect(rollup.ongoing, 3);
      expect(rollup.locked, 1);
      expect(rollup.removal, 1);
      expect(rollup.awaitingPayment, 1);
      expect(rollup.completed, 2);
      expect(rollup.cancelled, 1);
    });

    test('payout buckets: due only for completed unpaid, cancelled never counted', () {
      expect(rollup.payablePkr, 500); // completed + pending
      expect(rollup.expectedPkr, 350); // ongoing (incl. awaiting payment) + pending
      expect(rollup.paidPkr, 300); // paid, cancelled order's 999 excluded
      expect(rollup.dueSales.map((s) => s.id), ['3']);
    });

    test('billing excludes cancelled and keeps currencies apart', () {
      expect(rollup.billedUsd, 80);
      expect(rollup.receivedPkr, 14000);
      // Per order: -100, -200, -50, 14000-1000-500, -300 (cancelled excluded).
      expect(rollup.profitPkr, 11850);
    });

    test('completion rate counts cancelled against, ignores ongoing', () {
      expect(rollup.completionRate, closeTo(2 / 3, 1e-9)); // the awaiting-payment order is not concluded
      expect(SalesRollup(const []).completionRate, 0);
    });
  });

  group('fresh start (archived payments)', () {
    final rollup = SalesRollup([
      sale('old', 'Old Client', status: SaleStatus.completed, payout: 900, price: 100, received: 20000, archived: true),
      sale('old2', 'Old Client', status: SaleStatus.inProgress, payout: 400, archived: true),
      sale('new', 'New Client', status: SaleStatus.completed, payout: 500, price: 20, received: 5000, removal: 500),
    ]);

    test('archived orders still count as orders and keep their stage', () {
      expect(rollup.total, 3);
      expect(rollup.archived, 2);
      expect(rollup.completed, 2);
      expect(rollup.ongoing, 1);
    });

    test('but add nothing to payouts, billing or profit', () {
      expect(rollup.payablePkr, 500);
      expect(rollup.expectedPkr, 0);
      expect(rollup.paidPkr, 0);
      expect(rollup.billedUsd, 20);
      expect(rollup.receivedPkr, 5000);
      expect(rollup.profitPkr, 4000);
      expect(rollup.dueSales.map((s) => s.id), ['new']);
    });

    test('clients from before the fresh start are kept', () {
      final snap = AdminSnapshot(sales: rollup.sales, users: const []);
      expect(snap.clients.map((c) => c.name).toSet(), {'Old Client', 'New Client'});
    });
  });

  group('AdminSnapshot', () {
    final sales = [
      sale('1', 'Cafe Roma', salesmanId: 'u1', salesmanName: 'Ali Khan', status: SaleStatus.completed, createdAt: DateTime(2026, 10, 1)),
      sale('2', ' cafe roma ', salesmanId: 'u2', salesmanName: 'Sara', createdAt: DateTime(2026, 10, 5)),
      sale('3', 'Bistro', salesmanName: 'ali khan', createdAt: DateTime(2026, 10, 3)), // legacy: name only
      sale('4', 'Orphan', createdAt: DateTime(2026, 10, 2)),
    ];
    final snap = AdminSnapshot(sales: sales, users: const [ali, sara, boss, newbie]);

    test('salesmen exclude admins and keep unapproved accounts', () {
      final names = snap.salesmen.map((s) => s.user.name).toSet();
      expect(names, {'Ali Khan', 'Sara', 'Newbie'});
      expect(snap.pendingApprovals, 1);
    });

    test('a legacy sale with only a name is matched to its salesman', () {
      final alis = snap.salesmanFor('u1')!;
      expect(alis.sales.map((s) => s.id).toSet(), {'1', '3'});
      expect(snap.salesmanFor('u2')!.sales.map((s) => s.id), ['2']);
    });

    test('a sale tied to another id is not claimed by name', () {
      final clash = [sale('9', 'X', salesmanId: 'u2', salesmanName: 'Ali Khan')];
      expect(AdminSnapshot.salesOf(ali, clash), isEmpty);
    });

    test('clients group case- and whitespace-insensitively, newest activity first', () {
      expect(snap.clients.map((c) => c.name), ['Cafe Roma', 'Bistro', 'Orphan']);
      final roma = snap.clients.first;
      expect(roma.rollup.total, 2);
      expect(roma.isActive, isTrue);
      expect(roma.salesmen, ['Ali Khan', 'Sara']);
    });

    test('unassigned = no id and no name', () {
      expect(snap.unassigned.map((s) => s.id), ['4']);
    });
  });

  group('money formatting', () {
    test('groups thousands and rounds', () {
      expect(formatPkr(0), 'PKR 0');
      expect(formatPkr(12500), 'PKR 12,500');
      expect(formatPkr(1234567.6), 'PKR 1,234,568');
      expect(formatUsd(999), '\$999');
      expect(formatUsd(-1500), '\$-1,500');
    });
  });
}
