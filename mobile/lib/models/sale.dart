import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Deal-stage progression — mirrors `frontend/lib/domain/entities/sale.dart`
/// and backend/src/modules/sales/saleStore.js's LEAD_STATUSES exactly, since
/// all three read/write the same Firestore `sales` collection.
///
/// The sales process: the salesman locks the deal with the client
/// ([newSale]) → our team does the removal ([inProgress]) → the client is
/// asked to pay ([payment]) → the client pays and it is [completed].
enum SaleStatus {
  newSale,
  inProgress,
  payment,
  completed,
  cancelled;

  static SaleStatus fromJson(String? value) {
    switch (value) {
      case 'in_progress':
        return SaleStatus.inProgress;
      case 'payment':
        return SaleStatus.payment;
      case 'completed':
        return SaleStatus.completed;
      case 'cancelled':
        return SaleStatus.cancelled;
      case 'new':
      default:
        return SaleStatus.newSale;
    }
  }

  /// The value the backend stores and accepts (`leadStatus`).
  String get json => switch (this) {
        SaleStatus.newSale => 'new',
        SaleStatus.inProgress => 'in_progress',
        SaleStatus.payment => 'payment',
        SaleStatus.completed => 'completed',
        SaleStatus.cancelled => 'cancelled',
      };

  /// Still in the process: locked, in removal, or waiting on payment.
  bool get isOngoing => this == SaleStatus.newSale || this == SaleStatus.inProgress || this == SaleStatus.payment;

  /// The next step of the process, or null at the end (completed/cancelled).
  SaleStatus? get next => switch (this) {
        SaleStatus.newSale => SaleStatus.inProgress,
        SaleStatus.inProgress => SaleStatus.payment,
        SaleStatus.payment => SaleStatus.completed,
        SaleStatus.completed || SaleStatus.cancelled => null,
      };

  /// What moving to [next] means, as the action's label.
  String? get advanceLabel => switch (this) {
        SaleStatus.newSale => 'Start removal',
        SaleStatus.inProgress => 'Removal done — request payment',
        SaleStatus.payment => 'Client paid — complete deal',
        SaleStatus.completed || SaleStatus.cancelled => null,
      };

  String get label => switch (this) {
        SaleStatus.newSale => 'Deal locked',
        SaleStatus.inProgress => 'Removal',
        SaleStatus.payment => 'Payment',
        SaleStatus.completed => 'Completed',
        SaleStatus.cancelled => 'Cancelled',
      };
}

/// Has the employee/salesman been paid their cut (in PKR) — separate from
/// the client's USD payment, which this app never shows the salesman.
enum EmployeePaymentStatus {
  pending,
  paid;

  static EmployeePaymentStatus fromJson(String? value) {
    return value == 'paid' ? EmployeePaymentStatus.paid : EmployeePaymentStatus.pending;
  }

  String get label => this == EmployeePaymentStatus.paid ? 'Paid' : 'Pending';
}

/// Has the client paid what they were billed (USD). Admin-only — the
/// salesman app never reads or shows it. Values mirror the backend's
/// CLIENT_PAYMENT_STATUSES.
enum ClientPaymentStatus {
  pending('pending', 'Pending'),
  inProcess('in_process', 'In process'),
  received('received', 'Received'),
  paid('paid', 'Paid'),
  stuck('stuck', 'Stuck');

  const ClientPaymentStatus(this.json, this.label);

  final String json;
  final String label;

  static ClientPaymentStatus fromJson(String? value) {
    return ClientPaymentStatus.values.firstWhere(
      (s) => s.json == value,
      orElse: () => ClientPaymentStatus.pending,
    );
  }
}

class Sale extends Equatable {
  const Sale({
    required this.id,
    required this.businessName,
    this.reviewLink,
    this.clientId,
    this.salesmanId,
    this.salesmanName,
    this.status = SaleStatus.newSale,
    this.employeePaymentAmount = 0,
    this.employeePaymentStatus = EmployeePaymentStatus.pending,
    this.priceChargedToClient = 0,
    this.clientPaymentStatus = ClientPaymentStatus.pending,
    this.clientAmountReceived = 0,
    this.removalCost = 0,
    this.clientPaymentMethod,
    this.paymentsArchived = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String businessName;
  final String? reviewLink;

  /// The stored client this order belongs to, when it was created with one.
  final String? clientId;
  final String? salesmanId;
  final String? salesmanName;
  final SaleStatus status;

  /// What this salesman is paid for the order — PKR.
  final double employeePaymentAmount;
  final EmployeePaymentStatus employeePaymentStatus;

  /// Client-side billing, populated only by [Sale.fromJsonMap] (the admin
  /// REST feed). USD for the price; PKR for the received amount and costs.
  final double priceChargedToClient;
  final ClientPaymentStatus clientPaymentStatus;
  final double clientAmountReceived;
  final double removalCost;
  final String? clientPaymentMethod;

  /// True for orders from before the "fresh start": the order and its
  /// client are kept, but its payment figures are excluded from every
  /// payout, billing and profit total.
  final bool paymentsArchived;

  /// What is left of the client's payment after the salesman and removal
  /// costs — PKR, same formula as the backend's `computeProfit`.
  double get profit => clientAmountReceived - removalCost - employeePaymentAmount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Sale.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Sale(
      id: doc.id,
      businessName: (d['businessName'] as String?) ?? 'Unnamed business',
      reviewLink: d['reviewLink'] as String?,
      salesmanId: d['salesmanId'] as String?,
      salesmanName: d['salesmanName'] as String?,
      status: SaleStatus.fromJson(d['leadStatus'] as String?),
      employeePaymentAmount: (d['employeePaymentAmount'] as num?)?.toDouble() ?? 0,
      employeePaymentStatus: EmployeePaymentStatus.fromJson(d['employeePaymentStatus'] as String?),
      paymentsArchived: d['paymentsArchived'] == true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory Sale.fromJsonMap(Map<String, dynamic> d) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is Map && val['_seconds'] != null) {
        return DateTime.fromMillisecondsSinceEpoch((val['_seconds'] as num).toInt() * 1000);
      }
      return null;
    }
    return Sale(
      id: (d['id'] as String?) ?? '',
      businessName: (d['businessName'] as String?) ?? 'Unnamed business',
      reviewLink: d['reviewLink'] as String?,
      clientId: d['clientId'] as String?,
      salesmanId: d['salesmanId'] as String?,
      salesmanName: d['salesmanName'] as String?,
      status: SaleStatus.fromJson(d['leadStatus'] as String?),
      employeePaymentAmount: (d['employeePaymentAmount'] as num?)?.toDouble() ?? 0,
      employeePaymentStatus: EmployeePaymentStatus.fromJson(d['employeePaymentStatus'] as String?),
      priceChargedToClient: (d['priceChargedToClient'] as num?)?.toDouble() ?? 0,
      clientPaymentStatus: ClientPaymentStatus.fromJson(d['clientPaymentStatus'] as String?),
      clientAmountReceived: (d['clientAmountReceived'] as num?)?.toDouble() ?? 0,
      removalCost: (d['removalCost'] as num?)?.toDouble() ?? 0,
      clientPaymentMethod: d['clientPaymentMethod'] as String?,
      paymentsArchived: d['paymentsArchived'] == true,
      createdAt: parseDate(d['createdAt']),
      updatedAt: parseDate(d['updatedAt']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        businessName,
        reviewLink,
        clientId,
        salesmanId,
        salesmanName,
        status,
        employeePaymentAmount,
        employeePaymentStatus,
        priceChargedToClient,
        clientPaymentStatus,
        clientAmountReceived,
        removalCost,
        clientPaymentMethod,
        paymentsArchived,
      ];
}
