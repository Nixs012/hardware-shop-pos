import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/staff.dart';

class AuthService {
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Staff login / role check
  Future<Staff?> login(String email, String password) async {
    try {
      final trimmedEmail = email.trim();
      final lowerEmail = trimmedEmail.toLowerCase();
      
      // Authenticate with Firebase
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      if (userCredential.user != null) {
        // Try looking up by exactly what was entered
        var querySnapshot = await _firestore
            .collection('staff')
            .where('email', isEqualTo: trimmedEmail)
            .limit(1)
            .get();

        // If not found, fallback to lowercased version in case Firestore data differs
        if (querySnapshot.docs.isEmpty && trimmedEmail != lowerEmail) {
          querySnapshot = await _firestore
              .collection('staff')
              .where('email', isEqualTo: lowerEmail)
              .limit(1)
              .get();
        }

        if (querySnapshot.docs.isNotEmpty) {
          // Verify role (admin/cashier) is handled by the Staff model
          return Staff.fromMap(
            querySnapshot.docs.first.data(),
            querySnapshot.docs.first.id,
          );
        }
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}
