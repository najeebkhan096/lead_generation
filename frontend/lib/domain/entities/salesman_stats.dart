/// One day's count of new leads contacted, e.g. 2026-10-18 → 4.
class SalesmanDay {
  const SalesmanDay({required this.day, required this.count});

  /// 'YYYY-MM-DD' in the business day zone (Asia/Dubai).
  final String day;
  final int count;

  factory SalesmanDay.fromJson(Map<String, dynamic> json) {
    return SalesmanDay(
      day: (json['day'] as String?) ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One salesman's contact stats.
class SalesmanStat {
  const SalesmanStat({
    required this.id,
    required this.name,
    this.email,
    this.role = 'salesman',
    this.approved = false,
    this.dailyLeadLimit = 10,
    this.limitLeftToday = 0,
    this.contactedToday = 0,
    this.contactedLast7 = 0,
    this.contactedTotal = 0,
    this.activeDays = 0,
    this.averagePerActiveDay = 0,
    this.daysAtLimit = 0,
    this.firstContactAt,
    this.lastContactAt,
    this.daily = const [],
    this.hourlyToday = const [],
  });

  final String id;
  final String name;
  final String? email;
  final String role;
  final bool approved;
  final int dailyLeadLimit;
  final int limitLeftToday;
  final int contactedToday;
  final int contactedLast7;
  final int contactedTotal;
  final int activeDays;
  final double averagePerActiveDay;

  /// Days in the chart window on which this salesman reached the limit.
  final int daysAtLimit;
  final DateTime? firstContactAt;
  final DateTime? lastContactAt;

  /// One entry per day in the chart window, oldest first.
  final List<SalesmanDay> daily;

  /// Contacts today by hour of the day (0 to 23, Dubai time).
  final List<int> hourlyToday;

  factory SalesmanStat.fromJson(Map<String, dynamic> json) {
    return SalesmanStat(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Unnamed',
      email: json['email'] as String?,
      role: (json['role'] as String?) ?? 'salesman',
      approved: json['approved'] == true,
      dailyLeadLimit: (json['dailyLeadLimit'] as num?)?.toInt() ?? 10,
      limitLeftToday: (json['limitLeftToday'] as num?)?.toInt() ?? 0,
      contactedToday: (json['contactedToday'] as num?)?.toInt() ?? 0,
      contactedLast7: (json['contactedLast7'] as num?)?.toInt() ?? 0,
      contactedTotal: (json['contactedTotal'] as num?)?.toInt() ?? 0,
      activeDays: (json['activeDays'] as num?)?.toInt() ?? 0,
      averagePerActiveDay: (json['averagePerActiveDay'] as num?)?.toDouble() ?? 0,
      daysAtLimit: (json['daysAtLimit'] as num?)?.toInt() ?? 0,
      firstContactAt: _date(json['firstContactAt']),
      lastContactAt: _date(json['lastContactAt']),
      daily: [
        for (final d in (json['daily'] as List<dynamic>? ?? const [])) SalesmanDay.fromJson(d as Map<String, dynamic>),
      ],
      hourlyToday: [for (final n in (json['hourlyToday'] as List<dynamic>? ?? const [])) (n as num).toInt()],
    );
  }
}

/// Every salesman together, and the per-day totals for the overall chart.
class SalesmanStatsTotals {
  const SalesmanStatsTotals({
    this.contactedTotal = 0,
    this.contactedToday = 0,
    this.contactedLast7 = 0,
    this.activeSalesmen = 0,
    this.reviewLeads = 0,
    this.newLeft = 0,
    this.daily = const [],
    this.hourlyToday = const [],
  });

  /// Every new lead contacted by anyone, all time.
  final int contactedTotal;
  final int contactedToday;
  final int contactedLast7;
  final int activeSalesmen;

  /// Every 1-star WhatsApp lead, contacted or not.
  final int reviewLeads;

  /// 1-star WhatsApp leads nobody has contacted yet.
  final int newLeft;
  final List<SalesmanDay> daily;

  /// Everyone's contacts today by hour of the day (0 to 23, Dubai time).
  final List<int> hourlyToday;

  factory SalesmanStatsTotals.fromJson(Map<String, dynamic> json) {
    return SalesmanStatsTotals(
      contactedTotal: (json['contactedTotal'] as num?)?.toInt() ?? 0,
      contactedToday: (json['contactedToday'] as num?)?.toInt() ?? 0,
      contactedLast7: (json['contactedLast7'] as num?)?.toInt() ?? 0,
      activeSalesmen: (json['activeSalesmen'] as num?)?.toInt() ?? 0,
      reviewLeads: (json['reviewLeads'] as num?)?.toInt() ?? 0,
      newLeft: (json['newLeft'] as num?)?.toInt() ?? 0,
      daily: [
        for (final d in (json['daily'] as List<dynamic>? ?? const [])) SalesmanDay.fromJson(d as Map<String, dynamic>),
      ],
      hourlyToday: [for (final n in (json['hourlyToday'] as List<dynamic>? ?? const [])) (n as num).toInt()],
    );
  }
}

/// The whole stats payload from `GET /api/users/stats`.
class SalesmanStats {
  const SalesmanStats({
    required this.generatedAt,
    required this.today,
    required this.days,
    required this.totals,
    required this.salesmen,
  });

  final DateTime? generatedAt;

  /// Today's day in the business zone.
  final String today;

  /// The chart window, oldest first.
  final List<String> days;
  final SalesmanStatsTotals totals;

  /// Most contacts first.
  final List<SalesmanStat> salesmen;

  factory SalesmanStats.fromJson(Map<String, dynamic> json) {
    return SalesmanStats(
      generatedAt: _date(json['generatedAt']),
      today: (json['today'] as String?) ?? '',
      days: [for (final d in (json['days'] as List<dynamic>? ?? const [])) d as String],
      totals: SalesmanStatsTotals.fromJson((json['totals'] as Map<String, dynamic>?) ?? const {}),
      salesmen: [
        for (final s in (json['salesmen'] as List<dynamic>? ?? const [])) SalesmanStat.fromJson(s as Map<String, dynamic>),
      ],
    );
  }
}

DateTime? _date(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}
