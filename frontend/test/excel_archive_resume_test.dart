import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/domain/entities/email_validation.dart';
import 'package:lead_generation_app/domain/entities/excel_archive.dart';
import 'package:lead_generation_app/domain/entities/lead.dart';
import 'package:lead_generation_app/domain/entities/validation_start.dart';
import 'package:lead_generation_app/domain/entities/whatsapp_web_status.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/pages/excel_archive_leads_page.dart';

class _Repo implements LeadRepository {
  _Repo(this.leads, this.runs);

  final List<Lead> leads;
  List<ValidationRun> runs;
  final started = <({List<String> phones, Map<String, dynamic>? scope})>[];
  final discarded = <String>[];

  @override
  Future<List<Lead>> getExcelArchiveLeads(String id) async => leads;

  @override
  Future<List<ValidationRun>> listValidationRuns({String? collection, String? kind}) async {
    expect(collection, 'archive');
    return runs;
  }

  @override
  Future<void> discardValidationRun(String id) async {
    discarded.add(id);
    runs = [for (final r in runs) if (r.id != id) r];
  }

  @override
  Future<WhatsAppWebStatus> getWhatsAppWebStatus() async => const WhatsAppWebStatus(
        status: WhatsAppWebConnectionStatus.ready,
        safety: WhatsAppSafetyStatus(dailyCap: 100, remainingToday: 100),
      );

  @override
  Future<ValidationStart> validateExternalLeads(List<Map<String, dynamic>> leads, {bool recheck = false, Map<String, dynamic>? scope}) async {
    started.add((phones: [for (final l in leads) l['phone'] as String], scope: scope));
    return const ValidationStart(total: 1);
  }

  @override
  Future<WhatsAppValidationSnapshot> getWhatsAppValidationStatus() async =>
      const WhatsAppValidationSnapshot(active: true, status: 'running', total: 1, checked: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Lead _lead(String name, String where, String phone) => Lead(
      id: name,
      dbId: name,
      business: name,
      category: 'Cafe',
      location: where,
      phone: phone,
      badReview: const BadReview(stars: 1, text: 'cold', date: '1 day ago'),
    );

const _archive = ExcelArchive(id: 'arch-1', fileName: 'cafes.xlsx', downloadUrl: 'https://x', categories: ['Cafe']);

Future<_Repo> _pump(WidgetTester tester, List<ValidationRun> runs) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo([
    _lead('Alpha', 'Austin, TX', '+15125550001'),
    _lead('Bravo', 'Dallas, TX', '+15125550002'),
    _lead('Charlie', 'Miami, FL', '+15125550003'),
  ], runs);
  await tester.pumpWidget(RepositoryProvider<LeadRepository>.value(
    value: repo,
    child: MaterialApp(theme: AppTheme.light(), home: const ExcelArchiveLeadsPage(archive: _archive)),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  return repo;
}

const _stopped = ValidationRun(
  id: 'run-1',
  kind: 'whatsapp',
  status: 'interrupted',
  collection: 'archive',
  archiveId: 'arch-1',
  category: 'Cafe',
  states: ['TX'],
  total: 2,
  checked: 1,
  found: 1,
);

void main() {
  testWidgets('an interrupted validation of this archive is offered for Resume, with how far it got', (tester) async {
    await _pump(tester, [_stopped]);
    expect(find.text('Interrupted validation'), findsOneWidget);
    expect(find.textContaining('"Cafe" · TX · 1 of 2 checked · 1 on WhatsApp'), findsOneWidget);
  });

  testWidgets('another archive\'s stopped validation is not shown here', (tester) async {
    await _pump(tester, [
      const ValidationRun(id: 'other', kind: 'whatsapp', status: 'stopped', collection: 'archive', archiveId: 'arch-2', category: 'Cafe', total: 5),
    ]);
    expect(find.text('Stopped validation'), findsNothing);
    expect(find.text('Interrupted validation'), findsNothing);
  });

  testWidgets('Resume restores the category and states, asks only about those numbers, and retires the old record', (tester) async {
    final repo = await _pump(tester, [_stopped]);

    await tester.tap(find.widgetWithText(FilledButton, 'Resume'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Resume validating WhatsApp numbers?'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Validate')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(repo.started, hasLength(1));
    // Only the TX numbers (the saved scope), not Miami's.
    expect(repo.started.single.phones, ['+15125550001', '+15125550002']);
    expect(repo.started.single.scope, {'archiveId': 'arch-1', 'category': 'Cafe', 'states': ['TX']});
    // The new run is recorded by the backend; the old record is dropped.
    expect(repo.discarded, ['run-1']);
  });

  testWidgets('Discard forgets it without validating anything', (tester) async {
    final repo = await _pump(tester, [_stopped]);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Discard'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(repo.discarded, ['run-1']);
    expect(repo.started, isEmpty);
    expect(find.text('Interrupted validation'), findsNothing);
  });

  testWidgets('a validation started by hand says what it is validating', (tester) async {
    final repo = await _pump(tester, const []);
    await tester.tap(find.text('Selected states'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilterChip, 'FL (1)'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilledButton, 'Validate'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(TextButton, 'Validate'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(repo.started.single.phones, ['+15125550003']);
    expect(repo.started.single.scope, {'archiveId': 'arch-1', 'category': 'Cafe', 'states': ['FL']});
  });
}
