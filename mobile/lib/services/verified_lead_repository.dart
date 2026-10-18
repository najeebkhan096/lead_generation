import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Marks verified leads (`whatsappLeads`) contacted for the signed-in salesman,
/// or moves them back to New.
///
/// The `setWhatsAppLeadContacted` function does the write, because it enforces
/// the salesman's daily limit (set by an admin). Its refusals arrive as
/// [FirebaseFunctionsException]: `resource-exhausted` when the limit is reached,
/// `failed-precondition` when another salesman already contacted the lead.
class VerifiedLeadRepository {
  VerifiedLeadRepository({FirebaseFunctions? functions, String? Function()? currentUid})
      : _functions = functions,
        _currentUid = currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);

  final FirebaseFunctions? _functions;
  final String? Function() _currentUid;

  /// The signed-in salesman — the owner of the leads they contacted.
  String? get currentUid => _currentUid();

  Future<void> setContacted(String leadId, {required bool contacted}) async {
    final callable = (_functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'))
        .httpsCallable('setWhatsAppLeadContacted');
    await callable.call<dynamic>({'leadId': leadId, 'contacted': contacted});
  }
}
