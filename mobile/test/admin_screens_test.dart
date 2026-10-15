import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/models/client_record.dart';
import 'package:lead_mobile/models/sale.dart';
import 'package:lead_mobile/models/sales_user.dart';
import 'package:lead_mobile/pages/admin_navigation_page.dart';
import 'package:lead_mobile/services/admin_repository.dart';
import 'package:lead_mobile/theme/app_theme.dart';

class FakeAdminRepository extends AdminRepository {
  FakeAdminRepository({required this.users, required this.sales, List<ClientRecord>? clients}) : clients = clients ?? [];

  List<SalesUser> users;
  List<Sale> sales;
  List<ClientRecord> clients;
  final List<Map<String, dynamic>> createdSales = [];
  final List<(String id, Map<String, dynamic> body)> updates = [];
  final List<({bool restore, bool apply})> archiveCalls = [];
  int archiveMatches = 2;
  Object? failWith;

  @override
  Future<List<SalesUser>> listUsers() async => users;

  @override
  Future<List<ClientRecord>> listClients() async => clients;

  @override
  Future<ClientRecord> createClient({required String name, required String mapsUrl}) async {
    final c = ClientRecord(id: 'c${clients.length + 1}', name: name, mapsUrl: mapsUrl);
    clients = [...clients, c];
    return c;
  }

  @override
  Future<ClientRecord> updateClient(String id, {String? name, String? mapsUrl}) async {
    final old = clients.firstWhere((c) => c.id == id);
    final c = ClientRecord(id: id, name: name ?? old.name, mapsUrl: mapsUrl ?? old.mapsUrl);
    clients = [for (final x in clients) x.id == id ? c : x];
    return c;
  }

  @override
  Future<Sale> createSale(Map<String, dynamic> body) async {
    createdSales.add(body);
    final s = Sale(id: 'new${createdSales.length}', businessName: body['businessName'] as String, clientId: body['clientId'] as String?, reviewLink: body['reviewLink'] as String?, createdAt: DateTime(2026, 10, 20));
    sales = [s, ...sales];
    return s;
  }

  @override
  Future<List<Sale>> listSales() async {
    if (failWith != null) throw failWith!;
    return sales;
  }

  @override
  Future<ArchiveResult> archivePayments({required DateTime before, bool restore = false, bool apply = false}) async {
    archiveCalls.add((restore: restore, apply: apply));
    return ArchiveResult(matched: archiveMatches, updated: apply ? archiveMatches : 0, alreadyArchived: 0, totalSales: sales.length);
  }

  @override
  Future<Sale> updateSale(String saleId, Map<String, dynamic> body) async {
    updates.add((saleId, body));
    final old = sales.firstWhere((s) => s.id == saleId);
    final updated = Sale(
      id: old.id,
      businessName: old.businessName,
      salesmanId: old.salesmanId,
      salesmanName: old.salesmanName,
      status: body.containsKey('leadStatus') ? SaleStatus.fromJson(body['leadStatus'] as String?) : old.status,
      employeePaymentAmount: old.employeePaymentAmount,
      employeePaymentStatus: body['employeePaymentStatus'] == 'paid' ? EmployeePaymentStatus.paid : old.employeePaymentStatus,
      clientAmountReceived: (body['clientAmountReceived'] as num?)?.toDouble() ?? old.clientAmountReceived,
      removalCost: (body['removalCost'] as num?)?.toDouble() ?? old.removalCost,
      clientPaymentMethod: body['clientPaymentMethod'] as String? ?? old.clientPaymentMethod,
      paymentsArchived: body['paymentsArchived'] as bool? ?? old.paymentsArchived,
      createdAt: old.createdAt,
    );
    sales = [for (final s in sales) s.id == saleId ? updated : s];
    return updated;
  }
}

const _users = [
  SalesUser(id: 'u1', name: 'Ali Khan', email: 'ali@x.com', approved: true),
  SalesUser(id: 'u2', name: 'Sara Ahmed', email: 'sara@x.com', approved: true),
  SalesUser(id: 'u3', name: 'Zed Newcomer', email: 'zed@x.com'),
];

List<Sale> _sales() => [
      Sale(id: 's1', businessName: 'Cafe Roma', salesmanId: 'u1', salesmanName: 'Ali Khan', status: SaleStatus.inProgress, employeePaymentAmount: 1500, createdAt: DateTime(2026, 10, 10)),
      Sale(id: 's2', businessName: 'Cafe Roma', salesmanId: 'u1', salesmanName: 'Ali Khan', status: SaleStatus.completed, employeePaymentAmount: 2000, createdAt: DateTime(2026, 10, 2)),
      Sale(id: 's3', businessName: 'Bistro Nine', salesmanId: 'u2', salesmanName: 'Sara Ahmed', status: SaleStatus.completed, employeePaymentAmount: 800, employeePaymentStatus: EmployeePaymentStatus.paid, createdAt: DateTime(2026, 10, 5)),
      Sale(id: 's4', businessName: 'Gym One', status: SaleStatus.newSale, createdAt: DateTime(2026, 10, 12)),
    ];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<FakeAdminRepository> pumpAdmin(WidgetTester tester, {FakeAdminRepository? repo}) async {
    tester.view.physicalSize = const Size(900, 1900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final r = repo ?? FakeAdminRepository(users: _users, sales: _sales());
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: AdminNavigationPage(repository: r)));
    await settle(tester);
    return r;
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await settle(tester);
  }

  testWidgets('bottom bar has Overview, Salesmen, Sales, Clients, More', (tester) async {
    await pumpAdmin(tester);
    final labels = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();
    expect(labels, ['Overview', 'Salesmen', 'Sales', 'Clients', 'More']);
  });

  testWidgets('overview totals ongoing vs completed and flags what needs attention', (tester) async {
    await pumpAdmin(tester);
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Ongoing sales'), findsOneWidget);
    expect(find.textContaining('1 account is awaiting approval'), findsOneWidget);
    expect(find.textContaining('PKR 2,000 in payouts due'), findsOneWidget);
    expect(find.textContaining('1 sale has no salesman assigned'), findsOneWidget);
  });

  testWidgets('salesmen tab lists each salesman with their ongoing/completed/due', (tester) async {
    await pumpAdmin(tester);
    await openTab(tester, 'Salesmen');
    expect(find.text('Ali Khan'), findsOneWidget);
    expect(find.text('Sara Ahmed'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget); // Zed awaits approval
    expect(find.text('PKR 2,000'), findsOneWidget); // Ali's due payout
  });

  testWidgets('salesman page splits their sales into ongoing and completed', (tester) async {
    await pumpAdmin(tester);
    await openTab(tester, 'Salesmen');
    await tester.tap(find.text('Ali Khan'));
    await settle(tester);

    expect(find.text('Ongoing 1'), findsOneWidget);
    expect(find.text('Completed 1'), findsOneWidget);
    expect(find.textContaining('Mark PKR 2,000 as paid'), findsOneWidget);

    await tester.tap(find.text('Completed 1'));
    await settle(tester);
    expect(find.text('Oct 2, 2026'), findsOneWidget); // the completed order
  });

  testWidgets('sales tab: ongoing by default, completed on its tab, filter by salesman', (tester) async {
    await pumpAdmin(tester);
    await openTab(tester, 'Sales');
    expect(find.text('Ongoing 2'), findsOneWidget);
    expect(find.text('Completed 2'), findsOneWidget);
    expect(find.text('Gym One'), findsOneWidget);
    expect(find.text('Bistro Nine'), findsNothing);

    await tester.tap(find.text('Completed 2'));
    await settle(tester);
    expect(find.text('Bistro Nine'), findsOneWidget);

    final sara = find.widgetWithText(ChoiceChip, 'Sara Ahmed');
    await tester.ensureVisible(sara); // the chip row scrolls horizontally
    await tester.tap(sara);
    await settle(tester);
    expect(find.text('Cafe Roma'), findsNothing); // Ali's completed order filtered out
    expect(find.text('Bistro Nine'), findsOneWidget);
  });

  testWidgets('clients tab groups orders by business', (tester) async {
    await pumpAdmin(tester);
    await openTab(tester, 'Clients');
    expect(find.text('Cafe Roma'), findsOneWidget);
    expect(find.text('2 orders'), findsOneWidget);
    expect(find.text('Active 2'), findsOneWidget); // Cafe Roma + Gym One
    expect(find.text('Delivered 1'), findsOneWidget);

    await tester.tap(find.text('Cafe Roma'));
    await settle(tester);
    expect(find.text('Ongoing 1'), findsOneWidget);
    expect(find.text('Completed 1'), findsOneWidget);
    expect(find.text('Handled by'), findsOneWidget);
  });

  testWidgets('marking a payout paid sends the right payload and updates the screen', (tester) async {
    final repo = await pumpAdmin(tester);
    await openTab(tester, 'Sales');
    await tester.tap(find.text('Completed 2'));
    await settle(tester);
    await tester.tap(find.text('Cafe Roma'));
    await settle(tester);

    expect(find.text('Sale details'), findsOneWidget);
    await tester.tap(find.text('Mark payout as paid'));
    await settle(tester);

    expect(repo.updates.single.$1, 's2');
    expect(repo.updates.single.$2, {'employeePaymentStatus': 'paid'});
    expect(find.text('Mark payout as paid'), findsNothing);
    expect(find.text('Paid'), findsWidgets);
  });

  testWidgets('changing stage sends the backend value, not the enum name', (tester) async {
    final repo = await pumpAdmin(tester);
    await openTab(tester, 'Sales');
    await tester.tap(find.text('Gym One'));
    await settle(tester);

    final chip = find.widgetWithText(ChoiceChip, 'Removal');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await settle(tester);
    expect(repo.updates.single.$2, {'leadStatus': 'in_progress'});
  });

  testWidgets('a deal advances locked → removal → payment → completed, asking what the client paid at the end', (tester) async {
    final repo = await pumpAdmin(tester);
    await openTab(tester, 'Sales');
    await tester.tap(find.text('Gym One')); // starts as Deal locked
    await settle(tester);

    await tester.tap(find.text('Start removal'));
    await settle(tester);
    expect(repo.updates.last.$2, {'leadStatus': 'in_progress'});

    await tester.tap(find.text('Removal done — request payment'));
    await settle(tester);
    expect(repo.updates.last.$2, {'leadStatus': 'payment'});

    // Completing needs the received amount first.
    await tester.tap(find.text('Client paid — complete deal'));
    await settle(tester);
    expect(find.text('Client payment received'), findsOneWidget);
    await tester.tap(find.text('Complete deal'));
    await settle(tester);
    expect(find.text('Enter the amount received'), findsOneWidget);
    expect(repo.updates.last.$2, {'leadStatus': 'payment'}); // nothing sent yet

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount received'), '14000');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Wise'));
    await tester.pump();
    await tester.tap(find.text('Complete deal'));
    await settle(tester);

    expect(repo.updates.last.$2, {
      'leadStatus': 'completed',
      'clientPaymentStatus': 'paid',
      'clientAmountReceived': 14000,
      'removalCost': 0,
      'clientPaymentMethod': 'Wise',
    });
    expect(find.text('Client paid — complete deal'), findsNothing);
    expect(find.textContaining('The client has paid'), findsOneWidget);
  });

  testWidgets('fresh start previews, asks to confirm, then applies; cancelling writes nothing', (tester) async {
    final repo = await pumpAdmin(tester);
    await openTab(tester, 'More');

    await tester.tap(find.text('Start fresh from today'));
    await settle(tester);
    expect(find.text('Start fresh from today?'), findsOneWidget);
    expect(find.textContaining('2 earlier orders'), findsOneWidget);
    expect(repo.archiveCalls, [(restore: false, apply: false)]); // preview only

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(repo.archiveCalls, hasLength(1));

    await tester.tap(find.text('Start fresh from today'));
    await settle(tester);
    await tester.tap(find.text('Start fresh'));
    await settle(tester);
    expect(repo.archiveCalls.last, (restore: false, apply: true));
  });

  testWidgets('an earlier order stays listed but shows no payout and offers to count again', (tester) async {
    final repo = FakeAdminRepository(users: _users, sales: [
      Sale(id: 'old', businessName: 'Old Client', salesmanId: 'u1', salesmanName: 'Ali Khan', status: SaleStatus.completed, employeePaymentAmount: 900, paymentsArchived: true, createdAt: DateTime(2026, 9, 1)),
    ]);
    await pumpAdmin(tester, repo: repo);
    await openTab(tester, 'Clients');
    expect(find.text('Old Client'), findsOneWidget); // the client is kept

    await openTab(tester, 'Sales');
    await tester.tap(find.text('Completed 1'));
    await settle(tester);
    expect(find.text('Earlier order'), findsOneWidget);
    await tester.tap(find.text('Old Client'));
    await settle(tester);

    expect(find.text('Mark payout as paid'), findsNothing);
    await tester.tap(find.text('Count its payments again'));
    await settle(tester);
    expect(repo.updates.single.$2, {'paymentsArchived': false});
  });

  testWidgets('clients tab lists stored clients (even with no orders) and flags a missing map link', (tester) async {
    final repo = FakeAdminRepository(users: _users, sales: [], clients: [
      const ClientRecord(id: 'c1', name: 'Family Care Center', mapsUrl: 'https://maps.app.goo.gl/abc'),
      const ClientRecord(id: 'c2', name: 'Holy Moly'),
    ]);
    await pumpAdmin(tester, repo: repo);
    await openTab(tester, 'Clients');
    expect(find.text('Family Care Center'), findsOneWidget);
    expect(find.text('Holy Moly'), findsOneWidget);
    expect(find.text('Add map link'), findsOneWidget); // only the one without a link
    expect(find.text('No orders yet'), findsNWidgets(2));
  });

  testWidgets('adding a client needs a business name and a valid Google Maps link', (tester) async {
    final repo = await pumpAdmin(tester);
    await openTab(tester, 'Clients');
    await tester.tap(find.text('Add client'));
    await settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add client'));
    await settle(tester);
    expect(find.text('Enter the business name'), findsOneWidget);
    expect(find.text('Paste the Google Maps link'), findsOneWidget);
    expect(repo.clients, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Business name'), 'Blue Door Cafe');
    await tester.enterText(find.widgetWithText(TextFormField, 'Google Maps link'), 'not a link');
    await tester.tap(find.widgetWithText(FilledButton, 'Add client'));
    await settle(tester);
    expect(find.text('That is not a Google Maps link'), findsOneWidget);
    expect(repo.clients, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Google Maps link'), 'maps.app.goo.gl/XyZ123');
    await tester.tap(find.widgetWithText(FilledButton, 'Add client'));
    await settle(tester);

    expect(repo.clients.single.name, 'Blue Door Cafe');
    expect(repo.clients.single.mapsUrl, 'https://maps.app.goo.gl/XyZ123');
    expect(find.text('Blue Door Cafe'), findsOneWidget);
  });

  testWidgets('a sale for a new business creates the client with its link and references it', (tester) async {
    final repo = await pumpAdmin(tester);
    await openTab(tester, 'Sales');
    await tester.tap(find.text('Add sale'));
    await settle(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Client business'), 'Brand New Garage');
    await tester.pump();
    expect(find.text('Google Maps link'), findsOneWidget); // asked for because the client is new

    await tester.tap(find.widgetWithText(FilledButton, 'Add sale'));
    await settle(tester);
    expect(find.text('Paste the Google Maps link'), findsOneWidget);
    expect(repo.createdSales, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Google Maps link'), 'https://goo.gl/maps/NEW1');
    await tester.tap(find.widgetWithText(FilledButton, 'Add sale'));
    await settle(tester);

    expect(repo.clients.single.name, 'Brand New Garage');
    final sale = repo.createdSales.single;
    expect(sale['businessName'], 'Brand New Garage');
    expect(sale['clientId'], repo.clients.single.id);
    expect(sale['reviewLink'], 'https://goo.gl/maps/NEW1');
  });

  testWidgets('a sale for an existing client with a link does not ask for it again', (tester) async {
    final repo = FakeAdminRepository(users: _users, sales: _sales(), clients: [
      const ClientRecord(id: 'c1', name: 'Gym One', mapsUrl: 'https://maps.app.goo.gl/gym'),
    ]);
    await pumpAdmin(tester, repo: repo);
    await openTab(tester, 'Sales');
    await tester.tap(find.text('Add sale'));
    await settle(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Client business'), 'gym one');
    await tester.pump();
    expect(find.text('Google Maps link'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Add sale'));
    await settle(tester);
    final sale = repo.createdSales.single;
    expect(sale['businessName'], 'Gym One'); // the stored spelling wins
    expect(sale['clientId'], 'c1');
    expect(sale['reviewLink'], 'https://maps.app.goo.gl/gym');
    expect(repo.clients, hasLength(1)); // no duplicate client
  });

  testWidgets('a failed first load shows an error with retry', (tester) async {
    final repo = FakeAdminRepository(users: _users, sales: _sales())..failWith = Exception('Could not reach the server.');
    await pumpAdmin(tester, repo: repo);
    expect(find.text('Could not reach the server.'), findsWidgets);
    expect(find.text('Try again'), findsWidgets);

    repo.failWith = null;
    await tester.tap(find.text('Try again').first);
    await settle(tester);
    expect(find.text('Ongoing sales'), findsOneWidget);
  });
}
