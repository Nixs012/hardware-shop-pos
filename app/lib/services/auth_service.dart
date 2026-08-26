import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/staff.dart';

class AuthService {
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Staff login / role check
  Future<Staff?> login(String email, String password) async {
    try {
      // Authenticate with Firebase
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        // Fetch Staff record by authUid
        final querySnapshot = await _firestore
            .collection('staff')
            .where('auth_uid', isEqualTo: userCredential.user!.uid)
            .limit(1)
            .get();

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
