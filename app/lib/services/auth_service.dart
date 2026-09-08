import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;

import '../models/staff.dart';

class AuthService {
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Staff?> restoreCurrentStaff() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    return await _fetchStaffByUid(user.uid);
  }

  Future<Staff?> _fetchStaffByUid(String uid) async {
    final staffDocument = _firestore.collection('staff').doc(uid);

    try {
      final cacheSnapshot = await staffDocument.get(
        const GetOptions(source: Source.cache),
      );
      if (cacheSnapshot.exists) {
        return Staff.fromMap(cacheSnapshot.data()!, cacheSnapshot.id);
      }
    } catch (_) {
      // Ignore cache misses and continue to server fallback.
    }

    try {
      final serverSnapshot = await staffDocument.get(
        const GetOptions(source: Source.server),
      );
      if (serverSnapshot.exists) {
        return Staff.fromMap(serverSnapshot.data()!, serverSnapshot.id);
      }
    } catch (_) {
      // If the network is unavailable, keep the flow alive and allow the persisted
      // Firebase auth session to restore the app when the staff record is cached.
    }

    return null;
  }

  Future<Staff?> login(String email, String password) async {
    try {
      final trimmedEmail = email.trim();
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      if (userCredential.user == null) {
        return null;
      }

      return await _fetchStaffByUid(userCredential.user!.uid);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}
