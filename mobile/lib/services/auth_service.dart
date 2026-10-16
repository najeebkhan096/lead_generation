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
      lastError = _friendly(e.code, e.message);
      return null;
    } on PlatformException catch (e) {
      print('Error signing in with Google: $e');
      // e.g. ApiException 10 (this build's signing SHA-1 is not registered in
      // Firebase) or access_denied (account not allowed by the OAuth consent
      // screen). Both look like a plain "cancelled" otherwise.
      lastError = _friendly(e.code, e.message);
      return null;
    } catch (e) {
      print('Error signing in with Google: $e');
      lastError = 'Something went wrong. Please try again.';
      return null;
    }
  }

  /// A message a person can act on; the raw error stays in the log above.
  static String _friendly(String code, String? message) {
    final text = '$code ${message ?? ''}'.toLowerCase();
    if (text.contains('network') || text.contains('timeout') || text.contains('unavailable')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (text.contains('apiexception: 10') || text.contains('developer_error') || text.contains('sign_in_failed')) {
      return 'Google sign-in is not set up for this build. Contact the admin.';
    }
    if (text.contains('access_denied') || text.contains('user-disabled')) {
      return 'This Google account is not allowed to sign in.';
    }
    return 'Sign-in failed. Please try again.';
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
  /// is wrongly shown the error page. [failed] means the check itself errored
  /// (offline, rules), as opposed to the user simply not being approved.
  Future<({bool approved, bool isAdmin, bool failed})> loadAccess() async {
    final user = _auth.currentUser;
    if (user == null) return (approved: false, isAdmin: false, failed: false);
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var snap = await ref.get();
      if (!snap.exists) {
        await _upsertUserProfile(user);
        snap = await ref.get();
      }
      final data = snap.data();
      return (approved: data?['approved'] == true, isAdmin: data?['role'] == 'admin', failed: false);
    } catch (e) {
      print('Error loading access: $e');
      return (approved: false, isAdmin: false, failed: true);
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

  /// Always ends the Firebase session, even if Google's own sign-out fails
  /// (offline, plugin error); otherwise one failure there left the user
  /// signed in with a button that did nothing.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      print('Google sign-out failed (continuing): $e');
    }
    await _auth.signOut();
  }
}
