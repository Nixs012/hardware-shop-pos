import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../models/staff.dart';

class AuthService {
  final auth.FirebaseAuth _auth = auth.FirebaseAuth.instance;

  // Staff login / role check
  Future<Staff?> login(String email, String password) async {
    // Authenticate with Firebase
    // Fetch Staff record by authUid
    // Verify role (admin/cashier)
    return null; // Return staff
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}
