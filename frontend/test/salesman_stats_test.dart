import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/salesman_stats.dart';

void main() {
  test('parses the stats payload, salesmen and their daily chart', () {
    final stats = SalesmanStats.fromJson({
      'generatedAt': '2026-10-18T10:00:00.000Z',
      'today': '2026-10-18',
      'days': ['2026-10-17', '2026-10-18'],
      'totals': {
        'contactedTotal': 6,
        'contactedToday': 3,
        'contactedLast7': 4,
        'activeSalesmen': 2,
        'reviewLeads': 7,
        'newLeft': 1,
        'daily': [
          {'day': '2026-10-17', 'count': 1},
          {'day': '2026-10-18', 'count': 3},
        ],
      },
      'salesmen': [
        {
          'id': 'ali',
          'name': 'Ali',
          'email': 'ali@example.com',
          'approved': true,
          'dailyLeadLimit': 2,
          'limitLeftToday': 0,
          'contactedToday': 2,
          'contactedLast7': 3,
          'contactedTotal': 4,
          'activeDays': 3,
          'averagePerActiveDay': 1.3,
          'daysAtLimit': 1,
          'firstContactAt': '2026-10-10T06:00:00.000Z',
          'lastContactAt': '2026-10-18T09:00:00.000Z',
          'daily': [
            {'day': '2026-10-17', 'count': 1},
            {'day': '2026-10-18', 'count': 2},
          ],
        },
      ],
    });

    expect(stats.today, '2026-10-18');
    expect(stats.days, ['2026-10-17', '2026-10-18']);
    expect(stats.totals.newLeft, 1);
    expect(stats.totals.daily.last.count, 3);

    final ali = stats.salesmen.single;
    expect(ali.name, 'Ali');
    expect(ali.dailyLeadLimit, 2);
    expect(ali.limitLeftToday, 0);
    expect(ali.averagePerActiveDay, 1.3);
    expect(ali.daysAtLimit, 1);
    expect(ali.daily.map((d) => d.count), [1, 2]);
    expect(ali.lastContactAt, isNotNull);
  });

  test('a salesman with no contacts still parses, with zeros', () {
    final ali = SalesmanStat.fromJson({'id': 'x', 'name': 'New person'});
    expect(ali.dailyLeadLimit, 10);
    expect(ali.contactedTotal, 0);
    expect(ali.daily, isEmpty);
    expect(ali.firstContactAt, isNull);
  });
}
