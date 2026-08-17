import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/sale.dart';

/// Reads a salesman's own orders straight from Firestore's `sales`
/// collection — the same collection the web admin's Sales dashboard writes
/// to (see backend/src/services/saleStore.js). Mobile is read-only here:
/// payment status and amounts are set by admins on the web app.
///
/// `salesmanId` is the mobile app user's Firebase Auth uid — the same value
/// the web app picks from when assigning a sale (see
/// `frontend/.../lead_remote_datasource.dart`'s `listSalesmen()`, sourced
/// from `/api/users?role=salesman`). firestore.rules restricts reads of
/// this collection to `salesmanId == request.auth.uid`.
class SaleRepository {
  SaleRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Stream<List<Sale>> getSalesStream(String salesmanId) {
    return _db
        .collection('sales')
        .where('salesmanId', isEqualTo: salesmanId)
        .snapshots()
        .map((snap) => snap.docs.map(Sale.fromDoc).toList());
  }
}
