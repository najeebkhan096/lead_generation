import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Marks verified leads (`whatsappLeads` / `emailLeads`) contacted, or moves
/// them back to New. Writes only `status`, `contactedAt` and `contactedBy` —
/// the whole of what Firestore rules let a phone change on these documents —
/// and never `updatedAt`, which the lists are ordered by.
class VerifiedLeadRepository {
  VerifiedLeadRepository({FirebaseFirestore? firestore, String? Function()? currentUid})
      : _firestore = firestore,
        _currentUid = currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);

  final FirebaseFirestore? _firestore;
  final String? Function() _currentUid;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  Future<void> setContacted(String collection, String leadId, {required bool contacted}) {
    final uid = _currentUid();
    final updates = contacted
        ? <String, dynamic>{
            'status': 'contacted',
            'contactedAt': FieldValue.serverTimestamp(),
            'contactedBy': ?uid,
          }
        : <String, dynamic>{
            'status': 'lead',
            'contactedAt': FieldValue.delete(),
            'contactedBy': FieldValue.delete(),
          };
    return _db.collection(collection).doc(leadId).update(updates);
  }
}
