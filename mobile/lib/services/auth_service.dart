import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get user => _auth.authStateChanges();

  /// Why the last [signInWithGoogle] returned null, or null if the user just
  /// cancelled the account picker. Lets the login page say what went wrong.
  String? lastError;

  Future<User?> signInWithGoogle() async {
    lastError = null;
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
    } on FirebaseAuthException catch (e) {
      print('Error signing in with Google: $e');
      lastError = e.message ?? e.code;
      return null;
    } on PlatformException catch (e) {
      print('Error signing in with Google: $e');
      // e.g. ApiException 10 (this build's signing SHA-1 is not registered in
      // Firebase) or access_denied (account not allowed by the OAuth consent
      // screen). Both look like a plain "cancelled" otherwise.
      lastError = '${e.code}: ${e.message ?? ''}'.trim();
      return null;
    } catch (e) {
      print('Error signing in with Google: $e');
      lastError = e.toString();
      return null;
    }
  }

  Future<void> _upsertUserProfile(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    final data = <String, dynamic>{
      'name': user.displayName,
      'email': user.email,
      'photoURL': user.photoURL,
      'lastLoginAt': FieldValue.serverTimestamp(),
    };
    if (!snap.exists) {
      data['role'] = 'salesman';
      data['createdAt'] = FieldValue.serverTimestamp();
      data['approved'] = false;
    }
    await ref.set(data, SetOptions(merge: true));
    
    // Debug print
    final updatedSnap = await ref.get();
    print('=== [AuthService] User Profile Upserted ===');
    print('UID: ${user.uid}');
    print('Email: ${user.email}');
    print('Role: ${updatedSnap.data()?['role']}');
    print('Approved: ${updatedSnap.data()?['approved']}');
  }

  /// What the signed-in user may see: reads their profile, creating it first
  /// when it is missing. Signing in fires `authStateChanges` (and so the
  /// approval gate) before [signInWithGoogle] has written a first-time user's
  /// profile, so without this a new user's first check finds no document and
  /// is wrongly shown the error page.
  Future<({bool approved, bool isAdmin})> loadAccess() async {
    final user = _auth.currentUser;
    if (user == null) return (approved: false, isAdmin: false);
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var snap = await ref.get();
      if (!snap.exists) {
        await _upsertUserProfile(user);
        snap = await ref.get();
      }
      final data = snap.data();
      return (approved: data?['approved'] == true, isAdmin: data?['role'] == 'admin');
    } catch (e) {
      print('Error loading access: $e');
      return (approved: false, isAdmin: false);
    }
  }

  Future<bool> isCurrentUserApproved() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final approved = snap.data()?['approved'] == true;
      print('=== [AuthService] isCurrentUserApproved: $approved (UID: ${user.uid}) ===');
      return approved;
    } catch (e) {
      print('Error checking approval: $e');
      return false;
    }
  }

  Future<bool> isCurrentUserAdmin() async {
    final user = _auth.currentUser;
    if (user == null) {
      print('=== [AuthService] isCurrentUserAdmin: No current user logged in ===');
      return false;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final role = snap.data()?['role'];
      final isAdmin = role == 'admin';
      print('=== [AuthService] Check Admin Role ===');
      print('UID: ${user.uid}');
      print('Email: ${user.email}');
      print('Role found in Firestore: "$role"');
      print('Is Admin?: $isAdmin');
      return isAdmin;
    } catch (e) {
      print('Error checking admin role: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
