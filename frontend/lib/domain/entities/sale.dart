import 'package:equatable/equatable.dart';

/// Deal-stage progression — separate from either payment status below.
enum LeadStatus {
  newLead,
  inProgress,
  completed,
  cancelled;

  static LeadStatus fromJson(String? value) {
    switch (value) {
      case 'in_progress':
        return LeadStatus.inProgress;
      case 'completed':
        return LeadStatus.completed;
      case 'cancelled':
        return LeadStatus.cancelled;
      case 'new':
      default:
        return LeadStatus.newLead;
    }
  }

  String get json => switch (this) {
        LeadStatus.newLead => 'new',
        LeadStatus.inProgress => 'in_progress',
        LeadStatus.completed => 'completed',
        LeadStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        LeadStatus.newLead => 'New',
        LeadStatus.inProgress => 'In Progress',
        LeadStatus.completed => 'Completed',
        LeadStatus.cancelled => 'Cancelled',
      };
}

/// Has the client paid what they were charged (in USD).
enum ClientPaymentStatus {
  pending,
  paid,
  stuck,
  received,
  inProcess;

  static ClientPaymentStatus fromJson(String? value) {
    switch (value) {
      case 'paid':
        return ClientPaymentStatus.paid;
      case 'stuck':
        return ClientPaymentStatus.stuck;
      case 'received':
        return ClientPaymentStatus.received;
      case 'in_process':
        return ClientPaymentStatus.inProcess;
      case 'pending':
      default:
        return ClientPaymentStatus.pending;
    }
  }

  String get json => switch (this) {
        ClientPaymentStatus.pending => 'pending',
        ClientPaymentStatus.paid => 'paid',
        ClientPaymentStatus.stuck => 'stuck',
        ClientPaymentStatus.received => 'received',
        ClientPaymentStatus.inProcess => 'in_process',
      };

  String get label => switch (this) {
        ClientPaymentStatus.pending => 'Pending',
        ClientPaymentStatus.paid => 'Paid',
        ClientPaymentStatus.stuck => 'Stuck',
        ClientPaymentStatus.received => 'Received',
        ClientPaymentStatus.inProcess => 'In Process',
      };
}

/// Has the employee/salesman been paid their cut (in PKR) — separate from
/// the client's USD payment.
enum EmployeePaymentStatus {
  pending,
  paid;

  static EmployeePaymentStatus fromJson(String? value) {
    return value == 'paid' ? EmployeePaymentStatus.paid : EmployeePaymentStatus.pending;
  }

  String get json => this == EmployeePaymentStatus.paid ? 'paid' : 'pending';

  String get label => this == EmployeePaymentStatus.paid ? 'Paid' : 'Pending';
}

class Sale extends Equatable {
  const Sale({
    required this.id,
    required this.businessName,
    this.reviewLink,
    this.salesmanId,
    this.salesmanName,
    this.leadStatus = LeadStatus.newLead,
    this.priceChargedToClient = 0,
    this.clientPaymentStatus = ClientPaymentStatus.pending,
    this.clientPaymentMethod,
    this.employeePaymentAmount = 0,
    this.employeePaymentStatus = EmployeePaymentStatus.pending,
    this.clientAmountReceived = 0,
    this.removalCost = 0,
    this.profit = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String businessName;
  final String? reviewLink;
  final String? salesmanId;
  final String? salesmanName;
  final LeadStatus leadStatus;

  /// What the client is billed — USD.
  final double priceChargedToClient;
  final ClientPaymentStatus clientPaymentStatus;

  /// Free text, e.g. "UBL", "PayPal" — banks/rails vary too much for a fixed list.
  final String? clientPaymentMethod;

  /// What the employee/salesman is paid — PKR.
  final double employeePaymentAmount;
  final EmployeePaymentStatus employeePaymentStatus;

  /// Amount actually received from the client, converted — PKR.
  final double clientAmountReceived;

  /// Cost of fulfilling the service — PKR.
  final double removalCost;

  /// clientAmountReceived − removalCost − employeePaymentAmount, computed
  /// server-side — PKR. Never sum this with [priceChargedToClient]; they're
  /// different currencies.
  final double profit;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] as String,
      businessName: (json['businessName'] as String?) ?? '',
      reviewLink: json['reviewLink'] as String?,
      salesmanId: json['salesmanId'] as String?,
      salesmanName: json['salesmanName'] as String?,
      leadStatus: LeadStatus.fromJson(json['leadStatus'] as String?),
      priceChargedToClient: (json['priceChargedToClient'] as num?)?.toDouble() ?? 0,
      clientPaymentStatus: ClientPaymentStatus.fromJson(json['clientPaymentStatus'] as String?),
      clientPaymentMethod: json['clientPaymentMethod'] as String?,
      employeePaymentAmount: (json['employeePaymentAmount'] as num?)?.toDouble() ?? 0,
      employeePaymentStatus: EmployeePaymentStatus.fromJson(json['employeePaymentStatus'] as String?),
      clientAmountReceived: (json['clientAmountReceived'] as num?)?.toDouble() ?? 0,
      removalCost: (json['removalCost'] as num?)?.toDouble() ?? 0,
      profit: (json['profit'] as num?)?.toDouble() ?? 0,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  @override
  List<Object?> get props => [
        id,
        businessName,
        reviewLink,
        salesmanId,
        salesmanName,
        leadStatus,
        priceChargedToClient,
        clientPaymentStatus,
        clientPaymentMethod,
        employeePaymentAmount,
        employeePaymentStatus,
        clientAmountReceived,
        removalCost,
        profit,
        createdAt,
        updatedAt,
      ];
}

class StatusCount extends Equatable {
  const StatusCount({required this.count});

  final int count;

  factory StatusCount.fromJson(Map<String, dynamic>? json) {
    return StatusCount(count: (json?['count'] as num?)?.toInt() ?? 0);
  }

  @override
  List<Object?> get props => [count];
}

class SalesmanBreakdown extends Equatable {
  const SalesmanBreakdown({
    this.salesmanId,
    required this.salesmanName,
    required this.count,
    required this.revenueUsd,
    required this.employeePayoutPkr,
    required this.profitPkr,
    required this.completedCount,
  });

  final String? salesmanId;
  final String salesmanName;
  final int count;
  final double revenueUsd;
  final double employeePayoutPkr;
  final double profitPkr;
  final int completedCount;

  factory SalesmanBreakdown.fromJson(Map<String, dynamic> json) {
    return SalesmanBreakdown(
      salesmanId: json['salesmanId'] as String?,
      salesmanName: (json['salesmanName'] as String?) ?? 'Unassigned',
      count: (json['count'] as num?)?.toInt() ?? 0,
      revenueUsd: (json['revenueUsd'] as num?)?.toDouble() ?? 0,
      employeePayoutPkr: (json['employeePayoutPkr'] as num?)?.toDouble() ?? 0,
      profitPkr: (json['profitPkr'] as num?)?.toDouble() ?? 0,
      completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [salesmanId, salesmanName, count, revenueUsd, employeePayoutPkr, profitPkr, completedCount];
}

class SalesStats extends Equatable {
  const SalesStats({
    this.totalSales = 0,
    this.totalRevenueUsd = 0,
    this.totalEmployeePayoutPkr = 0,
    this.totalClientReceivedPkr = 0,
    this.totalRemovalCostPkr = 0,
    this.totalProfitPkr = 0,
    this.byLeadStatus = const {},
    this.byClientPaymentStatus = const {},
    this.byEmployeePaymentStatus = const {},
    this.bySalesman = const [],
  });

  final int totalSales;
  final double totalRevenueUsd;
  final double totalEmployeePayoutPkr;
  final double totalClientReceivedPkr;
  final double totalRemovalCostPkr;
  final double totalProfitPkr;
  final Map<LeadStatus, StatusCount> byLeadStatus;
  final Map<ClientPaymentStatus, StatusCount> byClientPaymentStatus;
  final Map<EmployeePaymentStatus, StatusCount> byEmployeePaymentStatus;
  final List<SalesmanBreakdown> bySalesman;

  factory SalesStats.fromJson(Map<String, dynamic> json) {
    final byLeadJson = (json['byLeadStatus'] as Map<String, dynamic>?) ?? const {};
    final byClientJson = (json['byClientPaymentStatus'] as Map<String, dynamic>?) ?? const {};
    final byEmployeeJson = (json['byEmployeePaymentStatus'] as Map<String, dynamic>?) ?? const {};
    final bySalesmanJson = (json['bySalesman'] as List<dynamic>?) ?? const [];
    return SalesStats(
      totalSales: (json['totalSales'] as num?)?.toInt() ?? 0,
      totalRevenueUsd: (json['totalRevenueUsd'] as num?)?.toDouble() ?? 0,
      totalEmployeePayoutPkr: (json['totalEmployeePayoutPkr'] as num?)?.toDouble() ?? 0,
      totalClientReceivedPkr: (json['totalClientReceivedPkr'] as num?)?.toDouble() ?? 0,
      totalRemovalCostPkr: (json['totalRemovalCostPkr'] as num?)?.toDouble() ?? 0,
      totalProfitPkr: (json['totalProfitPkr'] as num?)?.toDouble() ?? 0,
      byLeadStatus: byLeadJson.map((k, v) => MapEntry(LeadStatus.fromJson(k), StatusCount.fromJson(v as Map<String, dynamic>?))),
      byClientPaymentStatus: byClientJson
          .map((k, v) => MapEntry(ClientPaymentStatus.fromJson(k), StatusCount.fromJson(v as Map<String, dynamic>?))),
      byEmployeePaymentStatus: byEmployeeJson
          .map((k, v) => MapEntry(EmployeePaymentStatus.fromJson(k), StatusCount.fromJson(v as Map<String, dynamic>?))),
      bySalesman: bySalesmanJson.map((e) => SalesmanBreakdown.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  @override
  List<Object?> get props => [
        totalSales,
        totalRevenueUsd,
        totalEmployeePayoutPkr,
        totalClientReceivedPkr,
        totalRemovalCostPkr,
        totalProfitPkr,
        byLeadStatus,
        byClientPaymentStatus,
        byEmployeePaymentStatus,
        bySalesman,
      ];
}
