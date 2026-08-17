import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Deal-stage progression — mirrors `frontend/lib/domain/entities/sale.dart`
/// and backend/src/services/saleStore.js's LEAD_STATUSES exactly, since all
/// three read/write the same Firestore `sales` collection.
enum SaleStatus {
  newSale,
  inProgress,
  completed,
  cancelled;

  static SaleStatus fromJson(String? value) {
    switch (value) {
      case 'in_progress':
        return SaleStatus.inProgress;
      case 'completed':
        return SaleStatus.completed;
      case 'cancelled':
        return SaleStatus.cancelled;
      case 'new':
      default:
        return SaleStatus.newSale;
    }
  }

  String get label => switch (this) {
        SaleStatus.newSale => 'New',
        SaleStatus.inProgress => 'In Progress',
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

class Sale extends Equatable {
  const Sale({
    required this.id,
    required this.businessName,
    this.reviewLink,
    this.status = SaleStatus.newSale,
    this.employeePaymentAmount = 0,
    this.employeePaymentStatus = EmployeePaymentStatus.pending,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String businessName;
  final String? reviewLink;
  final SaleStatus status;

  /// What this salesman is paid for the order — PKR.
  final double employeePaymentAmount;
  final EmployeePaymentStatus employeePaymentStatus;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Sale.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Sale(
      id: doc.id,
      businessName: (d['businessName'] as String?) ?? 'Unnamed business',
      reviewLink: d['reviewLink'] as String?,
      status: SaleStatus.fromJson(d['leadStatus'] as String?),
      employeePaymentAmount: (d['employeePaymentAmount'] as num?)?.toDouble() ?? 0,
      employeePaymentStatus: EmployeePaymentStatus.fromJson(d['employeePaymentStatus'] as String?),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  @override
  List<Object?> get props => [id, businessName, status, employeePaymentAmount, employeePaymentStatus];
}
