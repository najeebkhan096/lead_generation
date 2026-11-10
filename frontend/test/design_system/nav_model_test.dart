import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/router/app_router.dart';
import 'package:lead_generation_app/presentation/widgets/nav_model.dart';

void main() {
  final items = [for (final g in navGroups) ...g.items];

  test('every sidebar destination is a real route (no fake navigation)', () {
    for (final item in items) {
      final match = appRouter.configuration.findMatch(Uri.parse(item.target));
      expect(match.isError, isFalse, reason: '${item.label} → ${item.path}');
    }
  });

  test('paths and labels are unique', () {
    expect({for (final i in items) i.target}.length, items.length);
    expect({for (final i in items) i.label}.length, items.length);
  });

  test('items sharing a branch differ by query, so they are told apart', () {
    final byBranch = <int, List<NavItem>>{};
    for (final i in items) {
      if (i.branch != null) byBranch.putIfAbsent(i.branch!, () => []).add(i);
    }
    for (final entry in byBranch.entries) {
      if (entry.value.length > 1) {
        expect(entry.value.every((i) => i.query.isNotEmpty), isTrue, reason: 'branch ${entry.key}');
      }
    }
  });

  group('navItemFor lights up the right item', () {
    String? label(String path) => navItemFor(path)?.label;

    test('exact and nested routes', () {
      expect(label('/'), 'Dashboard');
      expect(label('/leads'), '1-Star Reviews');
      expect(label('/leads/details'), '1-Star Reviews');
      expect(label('/jobs'), 'Jobs Finder');
      expect(label('/jobs/abc123'), 'Jobs Finder');
      expect(label('/salesman-stats/u1'), 'Salesman Stats');
      expect(label('/twilio-test/chat'), 'Twilio Test');
    });

    test('screens reached from another screen belong to it', () {
      expect(label('/scan-progress'), '1-Star Scan');
      expect(label('/multi-scan'), '1-Star Scan');
      expect(label('/whatsapp-verified'), 'WhatsApp Verified');
    });

    test('the two scan types light up their own item', () {
      expect(label('/scan'), '1-Star Scan');
      expect(label('/scan?type=no-website'), 'No-Website Scan');
      expect(label('/scan?type=reviews'), isNull, reason: 'an unknown type matches neither item');
    });

    test('tapping a scan item goes to its own URL', () {
      final scans = items.where((i) => i.path == '/scan').toList();
      expect(scans.map((i) => i.target), ['/scan', '/scan?type=no-website']);
    });

    test('the root does not swallow every other path', () {
      expect(label('/website-leads'), 'No Website');
      expect(label('/email-leads'), 'Email Leads');
      expect(label('/nowhere'), isNull);
    });
  });
}
