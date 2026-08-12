import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get user => _auth.authStateChanges();

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user != null) await _upsertUserProfile(user);
      return user;
    } catch (e) {
      print('Error signing in with Google: $e');
      return null;
    }
  }

  /// Every mobile app user is a salesman the web app can assign work to —
  /// creates the `users/{uid}` profile doc on first sign-in (role fixed at
  /// `salesman`, this app has no other kind of account) and refreshes
  /// name/email/photo + `lastLoginAt` on every subsequent sign-in without
  /// clobbering `createdAt`.
  Future<void> _upsertUserProfile(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    final data = <String, dynamic>{
      'name': user.displayName,
      'email': user.email,
      'photoURL': user.photoURL,
      'role': 'salesman',
      'lastLoginAt': FieldValue.serverTimestamp(),
    };
    if (!snap.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
