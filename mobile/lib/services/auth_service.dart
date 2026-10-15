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
