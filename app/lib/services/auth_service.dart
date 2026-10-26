import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;

import '../models/shop.dart';
import '../models/user_lookup.dart';
import '../models/staff.dart';
import 'sync_service.dart';

class AuthService {
  final auth.FirebaseAuth? _authInstance;
  final FirebaseFirestore? _firestoreInstance;

  AuthService({auth.FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _authInstance = auth,
        _firestoreInstance = firestore;

  auth.FirebaseAuth get _auth => _authInstance ?? auth.FirebaseAuth.instance;
  FirebaseFirestore get _firestore => _firestoreInstance ?? FirebaseFirestore.instance;

  Future<Staff?> restoreCurrentStaff() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    return await _fetchStaffByUid(user.uid);
  }

  Future<UserLookup?> _fetchUserLookup(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return UserLookup.fromMap(doc.data()!, doc.id);
      }
    } catch (_) {}
    return null;
  }

  Future<Staff?> _fetchStaffByUid(String uid) async {
    final userLookup = await _fetchUserLookup(uid);
    if (userLookup == null || !userLookup.active) {
      await _auth.signOut();
      return null;
    }

    final shopId = userLookup.shopId;
    final staffDoc = await _firestore
        .collection('shops')
        .doc(shopId)
        .collection('staff')
        .doc(uid)
        .get();

    if (staffDoc.exists && staffDoc.data() != null) {
      final staff = Staff.fromMap(staffDoc.data()!, staffDoc.id);
      return Staff(
        id: staff.id,
        name: staff.name,
        role: staff.role,
        email: staff.email,
        active: staff.active,
        pin: staff.pin,
        authUid: staff.authUid ?? uid,
        shopId: shopId,
      );
    }

    return Staff(
      id: uid,
      name: userLookup.name,
      role: userLookup.role,
      email: userLookup.email,
      active: userLookup.active,
      authUid: uid,
      shopId: shopId,
    );
  }

  Future<Staff?> login(String email, String password) async {
    try {
      final trimmedEmail = email.trim();
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        return null;
      }

      final userLookup = await _fetchUserLookup(user.uid);
      if (userLookup != null && !userLookup.active) {
        await _auth.signOut();
        throw Exception('This account has been deactivated.');
      }

      final staff = await _fetchStaffByUid(user.uid);
      if (staff != null && !staff.active) {
        await _auth.signOut();
        throw Exception('This account has been deactivated.');
      }
      return staff;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    await SyncService.instance.clearLocalCaches();
    await _auth.signOut();
  }

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<Staff> createShopAccount({
    required String fullName,
    required String email,
    required String password,
    required String shopName,
    required String address,
    required String phone,
    required String footer,
    required String paperSize,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw Exception('Failed to create user account.');
    }

    final uid = user.uid;
    final shopRef = _firestore.collection('shops').doc();
    final shopId = shopRef.id;
    final joinCode = _generateJoinCode();

    final shop = Shop(
      id: shopId,
      name: shopName.trim(),
      address: address.trim(),
      phone: phone.trim(),
      footer: footer.trim(),
      paperSize: paperSize,
      ownerUid: uid,
      joinCode: joinCode,
      createdAt: DateTime.now(),
    );

    final userLookup = UserLookup(
      uid: uid,
      shopId: shopId,
      role: 'admin',
      name: fullName.trim(),
      email: email.trim(),
      active: true,
    );

    final staff = Staff(
      id: uid,
      name: fullName.trim(),
      role: 'admin',
      email: email.trim(),
      active: true,
      authUid: uid,
      shopId: shopId,
    );

    try {
      final batch = _firestore.batch();
      batch.set(shopRef, shop.toMap());
      batch.set(_firestore.collection('users').doc(uid), userLookup.toMap());
      batch.set(
        _firestore.collection('shops').doc(shopId).collection('staff').doc(uid),
        staff.toMap(),
      );
      batch.set(_firestore.collection('joinCodes').doc(joinCode), {
        'shopId': shopId,
      });
      await batch.commit();

      try {
        await user.sendEmailVerification();
      } catch (_) {}

      return staff;
    } catch (e) {
      try {
        await user.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<Staff> joinAsCashier({
    required String fullName,
    required String email,
    required String password,
    required String joinCode,
  }) async {
    final normalizedCode = joinCode.trim().toUpperCase();
    final codeDoc =
        await _firestore.collection('joinCodes').doc(normalizedCode).get();

    if (!codeDoc.exists || codeDoc.data() == null) {
      throw Exception(
          'Invalid join code. Please check with your store administrator.');
    }

    final shopId = codeDoc.data()!['shopId'] as String;

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw Exception('Failed to create cashier user account.');
    }

    final uid = user.uid;

    final userLookup = UserLookup(
      uid: uid,
      shopId: shopId,
      role: 'cashier',
      name: fullName.trim(),
      email: email.trim(),
      active: true,
    );

    final staff = Staff(
      id: uid,
      name: fullName.trim(),
      role: 'cashier',
      email: email.trim(),
      active: true,
      authUid: uid,
      shopId: shopId,
    );

    try {
      final batch = _firestore.batch();
      batch.set(_firestore.collection('users').doc(uid), {
        ...userLookup.toMap(),
        'join_code': normalizedCode,
      });
      batch.set(
        _firestore.collection('shops').doc(shopId).collection('staff').doc(uid),
        {
          ...staff.toMap(),
          'join_code': normalizedCode,
        },
      );
      await batch.commit();

      try {
        await user.sendEmailVerification();
      } catch (_) {}

      return staff;
    } catch (e) {
      try {
        await user.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> createStaffAccount(
    String email,
    String password,
    Staff staffInfo,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('No authenticated admin found.');
    }

    final adminLookup = await _fetchUserLookup(currentUser.uid);
    final shopId = adminLookup?.shopId ?? staffInfo.shopId ?? 'default_shop';

    FirebaseApp secondaryApp = await Firebase.initializeApp(
      name: 'SecondaryAppForStaff',
      options: Firebase.app().options,
    );
    auth.User? createdUser;
    try {
      final credential = await auth.FirebaseAuth.instanceFor(
        app: secondaryApp,
      ).createUserWithEmailAndPassword(email: email.trim(), password: password);

      createdUser = credential.user;
      final uid = createdUser!.uid;
      final newStaff = Staff(
        id: uid,
        name: staffInfo.name,
        role: staffInfo.role.toLowerCase(),
        email: email.trim(),
        active: true,
        authUid: uid,
        shopId: shopId,
      );

      final userLookup = UserLookup(
        uid: uid,
        shopId: shopId,
        role: staffInfo.role.toLowerCase(),
        name: staffInfo.name,
        email: email.trim(),
        active: true,
      );

      final batch = _firestore.batch();
      batch.set(_firestore.collection('users').doc(uid), userLookup.toMap());
      batch.set(
        _firestore.collection('shops').doc(shopId).collection('staff').doc(uid),
        newStaff.toMap(),
      );
      await batch.commit();
    } finally {
      await secondaryApp.delete();
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('No authenticated user found. Please log in again.');
    }

    final credential = auth.EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  Future<void> deleteAccount(String password) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('No authenticated user found.');
    }

    final credential = auth.EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);

    final userLookup = await _fetchUserLookup(user.uid);
    if (userLookup != null) {
      try {
        await _firestore.collection('users').doc(user.uid).update({'active': false});
        await _firestore
            .collection('shops')
            .doc(userLookup.shopId)
            .collection('staff')
            .doc(user.uid)
            .update({'active': false});
      } catch (_) {}
    }

    await SyncService.instance.clearLocalCaches();
    await user.delete();
  }
}



