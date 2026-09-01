import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../models/staff.dart';

class AuthService {
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Staff?> restoreCurrentStaff() async {
    final user = _auth.currentUser;
    final email = user?.email?.trim();
    if (user == null || email == null || email.isEmpty) {
      return null;
    }

    return await _fetchStaffByEmail(email);
  }

  Future<Staff?> _fetchStaffByEmail(String rawEmail) async {
    final candidates = <String>{rawEmail.trim(), rawEmail.trim().toLowerCase()};

    for (final email in candidates) {
      try {
        final cacheSnapshot = await _firestore
            .collection('staff')
            .where('email', isEqualTo: email)
            .limit(1)
            .get(const GetOptions(source: Source.cache));

        if (cacheSnapshot.docs.isNotEmpty) {
          final doc = cacheSnapshot.docs.first;
          return Staff.fromMap(doc.data(), doc.id);
        }
      } catch (_) {
        // Ignore cache misses and continue to server fallback.
      }

      try {
        final serverSnapshot = await _firestore
            .collection('staff')
            .where('email', isEqualTo: email)
            .limit(1)
            .get(const GetOptions(source: Source.server));

        if (serverSnapshot.docs.isNotEmpty) {
          final doc = serverSnapshot.docs.first;
          return Staff.fromMap(doc.data(), doc.id);
        }
      } catch (_) {
        // If the network is unavailable, keep the flow alive and allow the persisted
        // Firebase auth session to restore the app when the staff record is already cached.
      }
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

      return await _fetchStaffByEmail(trimmedEmail);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}
