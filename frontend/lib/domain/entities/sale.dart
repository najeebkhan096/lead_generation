import 'package:equatable/equatable.dart';

enum SaleStatus {
  orderPlaced,
  clientPaid,
  paymentPendingPaypal,
  completed;

  static SaleStatus fromJson(String? value) {
    switch (value) {
      case 'client_paid':
        return SaleStatus.clientPaid;
      case 'payment_pending_paypal':
        return SaleStatus.paymentPendingPaypal;
      case 'completed':
        return SaleStatus.completed;
      case 'order_placed':
      default:
        return SaleStatus.orderPlaced;
    }
  }

  String get json => switch (this) {
        SaleStatus.orderPlaced => 'order_placed',
        SaleStatus.clientPaid => 'client_paid',
        SaleStatus.paymentPendingPaypal => 'payment_pending_paypal',
        SaleStatus.completed => 'completed',
      };

  String get label => switch (this) {
        SaleStatus.orderPlaced => 'Order Placed',
        SaleStatus.clientPaid => 'Client Paid',
        SaleStatus.paymentPendingPaypal => 'Payment Pending (PayPal)',
        SaleStatus.completed => 'Completed',
      };
}

class Sale extends Equatable {
  const Sale({
    required this.id,
    required this.businessName,
    this.reviewLink,
    this.salesmanId,
    this.salesmanName,
    this.price = 0,
    this.salesmanPrice = 0,
    this.status = SaleStatus.orderPlaced,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String businessName;
  final String? reviewLink;
  final String? salesmanId;
  final String? salesmanName;
  final double price;
  final double salesmanPrice;
  final SaleStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get profit => price - salesmanPrice;

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] as String,
      businessName: (json['businessName'] as String?) ?? '',
      reviewLink: json['reviewLink'] as String?,
      salesmanId: json['salesmanId'] as String?,
      salesmanName: json['salesmanName'] as String?,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      salesmanPrice: (json['salesmanPrice'] as num?)?.toDouble() ?? 0,
      status: SaleStatus.fromJson(json['status'] as String?),
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
        price,
        salesmanPrice,
        status,
        createdAt,
        updatedAt,
      ];
}

class SaleStatusBreakdown extends Equatable {
  const SaleStatusBreakdown({required this.count, required this.revenue});

  final int count;
  final double revenue;

  factory SaleStatusBreakdown.fromJson(Map<String, dynamic>? json) {
    return SaleStatusBreakdown(
      count: (json?['count'] as num?)?.toInt() ?? 0,
      revenue: (json?['revenue'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  List<Object?> get props => [count, revenue];
}

class SalesmanBreakdown extends Equatable {
  const SalesmanBreakdown({
    this.salesmanId,
    required this.salesmanName,
    required this.count,
    required this.revenue,
    required this.payout,
    required this.profit,
    required this.completedCount,
  });

  final String? salesmanId;
  final String salesmanName;
  final int count;
  final double revenue;
  final double payout;
  final double profit;
  final int completedCount;

  factory SalesmanBreakdown.fromJson(Map<String, dynamic> json) {
    return SalesmanBreakdown(
      salesmanId: json['salesmanId'] as String?,
      salesmanName: (json['salesmanName'] as String?) ?? 'Unassigned',
      count: (json['count'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
      payout: (json['payout'] as num?)?.toDouble() ?? 0,
      profit: (json['profit'] as num?)?.toDouble() ?? 0,
      completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [salesmanId, salesmanName, count, revenue, payout, profit, completedCount];
}

class SalesStats extends Equatable {
  const SalesStats({
    this.totalSales = 0,
    this.totalRevenue = 0,
    this.totalSalesmanPayout = 0,
    this.totalProfit = 0,
    this.byStatus = const {},
    this.bySalesman = const [],
  });

  final int totalSales;
  final double totalRevenue;
  final double totalSalesmanPayout;
  final double totalProfit;
  final Map<SaleStatus, SaleStatusBreakdown> byStatus;
  final List<SalesmanBreakdown> bySalesman;

  factory SalesStats.fromJson(Map<String, dynamic> json) {
    final byStatusJson = (json['byStatus'] as Map<String, dynamic>?) ?? const {};
    final bySalesmanJson = (json['bySalesman'] as List<dynamic>?) ?? const [];
    return SalesStats(
      totalSales: (json['totalSales'] as num?)?.toInt() ?? 0,
      totalRevenue: (json['totalRevenue'] as num?)?.toDouble() ?? 0,
      totalSalesmanPayout: (json['totalSalesmanPayout'] as num?)?.toDouble() ?? 0,
      totalProfit: (json['totalProfit'] as num?)?.toDouble() ?? 0,
      byStatus: byStatusJson.map(
        (k, v) => MapEntry(SaleStatus.fromJson(k), SaleStatusBreakdown.fromJson(v as Map<String, dynamic>?)),
      ),
      bySalesman: bySalesmanJson.map((e) => SalesmanBreakdown.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  @override
  List<Object?> get props => [totalSales, totalRevenue, totalSalesmanPayout, totalProfit, byStatus, bySalesman];
}
